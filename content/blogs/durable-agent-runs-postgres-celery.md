---
title: "We Didn't Need Temporal: Durable Agent Runs on Postgres and Celery"
date: 2026-07-03T10:00:00+08:00
draft: false
description: "How we built durable, crash-safe, long-running conversational agents on a single Postgres table and Celery, without a workflow engine like Temporal."
tags: [python, django, celery, postgresql, ai-agents, llm, backend, durable-execution, workflow-orchestration, temporal, distributed-systems]
---

We recently shipped long-running conversational agents at a CRM for small businesses. An agent attaches itself to a WhatsApp conversation and works it for hours or days: wake up, look at the conversation, maybe send a message, decide when to wake up next, go back to sleep. Eventually it finishes, or a human takes over, or the lead goes quiet, or something breaks.

When we sketched the requirements, they read like a brochure for a workflow engine:

- runs must survive worker crashes, deploys, and timeouts
- two workers must never execute the same run at the same time
- state must persist between wake-ups
- every run must end in a known, queryable state, including the ones that end badly

Our first instinct was the same as yours: Temporal, or a durable-execution library, or one of the agent frameworks that ship their own orchestration. We ended up building it on two primitives we already ran in production, a Postgres table and Celery, and the whole engine is small enough to read in one sitting. This post walks through the five decisions that made that possible.

To be clear about the claim up front: Temporal is a great tool, and it does far more than we needed. Durable timers, sagas, versioned workflows, cross-service orchestration. That was part of the problem. Adopting it meant standing up, learning, and operating a new piece of infrastructure, and we needed that time to ship the feature, not the platform. So this is not "workflow engines are bad." It is "our requirements were met by boring primitives we already ran in production, and yours might be too." The honest limits are at the end.

## The scheduler is one column

There is no scheduler component. There is a row per attached agent, and a nullable timestamp:

```python
class AgentScheduledRun(models.Model):
    conversation   = models.ForeignKey(Conversation, on_delete=models.CASCADE)
    agent_instance = models.ForeignKey(AgentInstance, on_delete=models.CASCADE)
    status         = EnumField(ScheduledRunStatus, default=ScheduledRunStatus.IN_PROGRESS)
    next_run_at    = models.DateTimeField(null=True, blank=True, db_index=True)
    context_data   = models.JSONField(default=dict)   # persistent state, more below
    budget         = models.JSONField(default=dict)   # cost tracking, a later post
    started_at     = models.DateTimeField(auto_now_add=True)
    resolved_at    = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [models.Index(fields=['status', 'next_run_at'])]
```

`next_run_at` is the entire scheduling mechanism. A run that should execute in six hours is a row where `next_run_at` is six hours from now. A beat task sweeps for due rows and fans them out:

```python
def filter_due(self):
    return self.filter(status=ScheduledRunStatus.IN_PROGRESS,
                       next_run_at__lte=timezone.now())

@shared_task
def find_due_scheduled_runs():
    due_ids = (AgentScheduledRun.objects.filter_due()
               .order_by('next_run_at')
               .values_list('pk', flat=True)[:100])
    for run_id in due_ids:
        process_scheduled_run.delay(run_id)
```

That is the whole thing. Rescheduling an agent is an UPDATE. Cancelling one is an UPDATE. Inspecting everything due in the next hour is a SELECT you can run in a shell at 2am. Every operational question about the system is a query against one indexed table, which is worth more in an incident than any dashboard we could have built.

The obvious objection is polling latency: the sweep runs on an interval, so "run at 14:00:00" really means "run within a sweep-interval after 14:00:00." For agents that think in minutes and hours, that is nothing. If you need sub-second precision, this design is wrong for you, and that is one of the honest limits.

## The line that makes it crash-safe

Here is the task that executes a due run. One line in it does more work than everything else in this post:

```python
@shared_task(time_limit=5 * 60)
def process_scheduled_run(run_id):
    with transaction.atomic():
        run_obj = (AgentScheduledRun.objects
                   .select_for_update(skip_locked=True)
                   .filter(pk=run_id)
                   .filter_due()
                   .first())
        if not run_obj:
            return
        # the load-bearing line:
        run_obj.next_run_at = timezone.now() + timedelta(hours=1)
        run_obj.save(update_fields=['next_run_at', 'updated_at'])

    try:
        action = resolve_action(run_obj)   # the agent implementation
        result = action.run_scheduled(run_obj)
    except Exception:
        record_run_failure(run_obj)
        return

    apply_result(run_obj, result)
```

Before the agent executes, we push its `next_run_at` one hour into the future and commit. This looks backwards, since we haven't run anything yet and we're already scheduling the retry, and that is exactly the point. It is a lease.

Walk through the failure modes:

- **Worker runs out of memory (OOM) mid-run, pod gets killed in a deploy, Celery hard time-limit fires.** No exception handler runs. With most designs, this run is now in limbo: it is `IN_PROGRESS`, nothing will touch it again, and you find out when a customer asks why the agent went silent. With the lease, nothing needs to happen. The row comes due again in an hour and the sweep picks it up. A dead worker costs one hour of latency, not a stuck agent.
- **The agent finishes normally.** `apply_result` overwrites the lease with the agent's real decision (reschedule for later, or terminate). The one-hour value never survives a successful run.
- **The agent raises.** The exception path records the failure (more below) and leaves the lease in place, so the retry is already scheduled. The error handler doesn't have to remember to reschedule. Forgetting to reschedule in an error path is precisely the bug that creates zombie runs, and this design makes it unwritable.

Two supporting details. The Celery `time_limit` is deliberately far below the lease duration, so a hung task is killed long before the row comes due again, and the lease can't double-fire. And because a crashed run re-executes, agent implementations must keep their side effects idempotent; that is a contract we impose on agent authors, documented on the base class, not something the framework can do for them.

One UPDATE, issued at the right moment, gave us the headline feature of the heavyweight tools: durable execution.

## Two workers, one row

The sweep-and-fan-out shape has a classic race: sweep N runs, sweep N+1 fires before the tasks from sweep N finish, both queues now hold a task for the same run. Or an operator enqueues a run manually while the sweep also picked it up.

The lock closes it:

```python
run_obj = (AgentScheduledRun.objects
           .select_for_update(skip_locked=True)
           .filter(pk=run_id)
           .filter_due()
           .first())
if not run_obj:
    return
```

Three things compound here:

- `select_for_update` means the second worker can't read the row while the first holds it.
- `skip_locked=True` means the second worker doesn't wait for the lock; it gets nothing and exits. Blocking would be worse than useless: the loser would wait out the winner and then execute the same run again.
- `.filter_due()` re-checked *inside* the transaction is the subtle one. Suppose worker B's task was queued while the run was due, but worker A finished and released the lock before B started. No lock contention, so `skip_locked` doesn't save you. But A's lease already moved `next_run_at` an hour out, so the row no longer matches `filter_due()`, and B gets nothing.

The due-check doubles as the cancellation path. Detaching an agent (user turned it off, human took over the conversation) is an UPDATE that sets a terminal status. Any task already sitting in the queue for that run arrives, fails the `IN_PROGRESS` filter, and exits. We never have to hunt down queued Celery tasks; they defuse themselves.

## Agents can't return nonsense

Every agent wake-up returns exactly one of two outcomes: *reschedule me at this time* or *I'm done, for this reason*. We encode that as a dataclass that refuses to be constructed in an invalid state:

```python
class ScheduledRunOutcome(enum.Enum):
    RESCHEDULE = "RESCHEDULE"
    TERMINAL   = "TERMINAL"

@dataclass
class ScheduledRunResult:
    outcome:         ScheduledRunOutcome
    next_run_at:     Optional[datetime] = None
    terminal_status: Optional[ScheduledRunStatus] = None
    agent_state:     Optional[BaseAgentState] = None

    def __post_init__(self):
        if self.outcome == ScheduledRunOutcome.RESCHEDULE:
            if self.next_run_at is None:
                raise ValueError("RESCHEDULE requires next_run_at")
            if self.next_run_at <= timezone.now():
                raise ValueError("RESCHEDULE requires a future next_run_at")
            if self.terminal_status is not None:
                raise ValueError("RESCHEDULE must not set terminal_status")
        elif self.outcome == ScheduledRunOutcome.TERMINAL:
            if self.terminal_status is None:
                raise ValueError("TERMINAL requires an ending status")
            if self.terminal_status == ScheduledRunStatus.IN_PROGRESS:
                raise ValueError("TERMINAL requires an ending status")
            if self.next_run_at is not None:
                raise ValueError("TERMINAL must not set next_run_at")
```

This is ordinary defensive code, but placement is everything. The framework has exactly one function, `apply_result`, that translates a result into row updates, and because invalid combinations raise at construction, inside the agent's own stack trace, `apply_result` never has to wonder what "TERMINAL but also reschedule me Tuesday" means. In a system where the agent logic is the part that changes weekly (new agent types, new exit conditions, prompt-driven behavior), making the framework's write path boring and total was the single best robustness investment. Bugs surface as a `ValueError` naming the broken invariant, in the agent that caused it, not as a row in a state nobody designed.

A related rule with the same flavor: `run_scheduled` receives the row as a read-only handle. Agents never call `save()`; the returned result is the only write path. One choke point for every mutation means one place to reason about concurrency, and it is the function you already read.

## State, self-healing, and free analytics

Between wake-ups, agent state lives in the row's `context_data` JSON, namespaced into two halves: `workflow` belongs to the framework, `agent` belongs to the agent. Agents define their state as a dataclass over JSON-native fields and never touch the raw dict:

```python
@dataclass
class LeadQualificationState(BaseAgentState):
    answers: dict = field(default_factory=dict)
    iterations: int = 0
    last_processed_at: str = ''   # iso string, never datetime
```

The framework's half of the namespace pays for itself with self-healing. Remember the exception path in `process_scheduled_run`. It calls `record_run_failure`, which increments a consecutive-failure counter in `workflow` and detaches the run when it hits a threshold:

```python
def record_run_failure(run):
    failures = (run.workflow_context.get('consecutive_failures') or 0) + 1
    ...  # persist the counter
    if failures >= 3:
        detach(run, ScheduledRunStatus.REMOVED_BY_SYSTEM)
```

And `apply_result` resets the counter to zero whenever a run succeeds. It is a *consecutive* counter, so one transient LLM-provider outage doesn't slowly poison a long-lived agent that otherwise works. An agent that fails three wake-ups in a row is genuinely broken for that conversation, and it removes itself instead of burning an hourly retry forever. When we count the moving parts an unattended agent fleet actually needs, this counter ranks above almost everything the fancy tools advertise.

Which leaves the question every stakeholder eventually asks: how do these runs end? We answered it by refusing to have a generic "DONE" status:

```python
class ScheduledRunStatus(enum.Enum):
    IN_PROGRESS        = "IN_PROGRESS"
    COMPLETED          = "COMPLETED"            # agent achieved its goal
    EXITED_ON_OUTBOUND = "EXITED_ON_OUTBOUND"   # a human replied. agent yielded
    EXITED_ON_INBOUND  = "EXITED_ON_INBOUND"    # some agents reuqire this as per their behaviour
    REMOVED_BY_USER    = "REMOVED_BY_USER"      # user turned the agent off
    REMOVED_BY_SYSTEM  = "REMOVED_BY_SYSTEM"    # failure threshold hit
```

Every terminal status names the *reason* the run ended. `GROUP BY status` on this table is the product dashboard: completion rate, human-takeover rate, failure rate. No events pipeline, no instrumentation sprint. If your terminal state is a boolean, you will retrofit this the first time someone asks "why did it stop for this customer?", and you will retrofit it without the historical data.

## What we actually gave up

Being truthful about the other side of the trade:

- **Scheduling precision.** Wake-ups land within a sweep interval of the target, not on it. Fine for hours-scale agents; wrong for seconds-scale jobs.
- **At-least-once, not exactly-once.** The lease guarantees a crashed run re-executes; it cannot make the crashed attempt un-happen. Idempotent side effects are mandatory and enforced only by convention and review.
- **No orchestration vocabulary.** Fan-out/fan-in, sagas across services, child workflows, versioned workflow migrations, none of that exists here. Our runs are independent, single-conversation loops; the moment they need to coordinate with each other, we would be re-deriving Temporal badly, and that is when we would adopt it.
- **One database.** The scheduler's availability is the primary DB's availability. That was already true of our product, so it cost nothing. It might not be true of yours.

None of these bit us, because none of them are in the requirements for "an agent babysits a conversation for a day." That is the actual lesson, and it generalizes past agents: the durable-execution features you need, survive crashes, never double-run, resume state, end in a known status, are separable from the orchestration features you are told come with them. The first list is a table, a lease, a lock, and two strict contracts. Read your requirements before you read the framework docs; you may already be running your workflow engine.
