---
title: "Conversational AI Agents: Reply to Conversations, Not Messages"
date: 2026-07-09T10:00:00+08:00
draft: false
description: "Why a chat agent should attach to a conversation and poll its state instead of replying per message, and how it decides when to speak, wait, and stop."
tags: [python, django, celery, ai-agents, llm, conversational-ai, whatsapp, chatbot, backend, event-driven, lead-qualification]
---

In the [last post](/blogs/durable-agent-runs-postgres-celery/) we built the engine: a Postgres row per attached agent, `next_run_at` as the scheduler, a lease for crash safety. This post is about the loop that runs on top of it, how a WhatsApp lead-qualification agent at a CRM for small businesses decides when to speak, when to wait, and when to shut up.

The agent's job is simple to state: a lead messages a business (say, a car dealership), the agent attaches to the conversation, works through a configured list of qualification questions (which model, what timeline, what budget, trade-in, test-drive day) and detaches when it is done or when a human takes over. The LLM parts (extraction, confidence scores, prompt defenses) are the next post. This one is about everything around the LLM, which is where the product actually lives.

## Handle the burst, not one stale message

Here is what a real lead looks like on WhatsApp:

```
14:02:11  lead: hi
14:02:19  lead: saw your ad for the RAV4
14:02:34  lead: looking for a family car, we are 5 people
```

Three messages in twenty-three seconds. Messaging platforms deliver them as three separate webhooks, and the natural architecture (webhook fires, agent replies) produces an agent that answers three times: a greeting to the "hi", something generic to the ad mention, and finally a real reply to the family-car message. Nobody reads that transcript and thinks "helpful assistant." They think "broken bot."

The fix that shaped our whole design: **the agent never responds to a message. It attaches to the conversation and polls its state.** A webhook's only job is to update the conversation row and nudge the schedule. The agent wakes up later, reads the conversation as a whole, and responds to where it is *now*.

Concretely, the inbound pipeline does two writes and gets out:

```python
def run_for_message(self, message_text, sender_phone):
    conversation, _ = Conversation.get_or_create_active(self.waba, sender_phone)
    Conversation.objects.filter(pk=conversation.pk).update(
        last_inbound_at=timezone.now(),
        updated_at=timezone.now(),
    )
    bump_next_run_for_attached_agents(conversation)
    ...
```

The bump is the debounce. Each long-running agent declares how long it wants to wait after an inbound message before it looks:

```python
class LeadQualificationAction(BaseLongRunningAction):
    state_class = LeadQualificationState
    bump_on_inbound_by_seconds = 30
```

and the bump pushes every attached run's `next_run_at` forward by that amount:

```python
def bump_next_run_for_attached_agents(conversation):
    # every inbound message pushes next_run_at forward;
    # runs with bump_on_inbound_by_seconds=null are not touched
    now = timezone.now()
    runs = (conversation.scheduled_runs.filter_in_progress()
            .filter(bump_on_inbound_by_seconds__isnull=False)
            .values_list('pk', 'bump_on_inbound_by_seconds'))
    for pk, bump_seconds in runs:
        AgentScheduledRun.objects.filter_in_progress().filter(pk=pk).update(
            next_run_at=now + timedelta(seconds=bump_seconds),
            updated_at=now,
        )
```

The mechanics fall out of the engine for free. `next_run_at` is already the scheduler, so debouncing is just an UPDATE: message one schedules the agent 30 seconds out, message two arrives 8 seconds later and moves it another 30 seconds out, message three moves it again. The agent wakes once, 30 seconds after the lead *stops typing*, and sees the whole burst as one unit of conversation. Classic trailing-edge debounce, implemented in the column we already had.

Thirty seconds of silence is a long time to leave a hot lead hanging, so attachment also fires a static introduction message, no LLM, sent instantly from config:

> "Hi! Thanks for reaching out to Horizon Toyota. You have come to the right place - give me a moment and I will be right with you."

The intro buys the debounce window. The lead gets an instant acknowledgement; the agent gets 30 quiet seconds to let the burst finish before its first real turn.

## The wake-up is a poll, not a callback

Because nothing pushes events to the agent, every wake-up asks the same question: *what is true about this conversation right now?* The agent's persistent state (the `agent` half of the run's `context_data` from the last post) is a small dataclass:

```python
@dataclass
class LeadQualificationState(BaseAgentState):
    answers: dict = field(default_factory=dict)   # per-question, with confidence
    iterations: int = 0
    nudge_index: int = 0
    next_nudge_at: str = ''
    last_processed_at: str = ''                    # iso string, never datetime
    gave_up: bool = False
```

and `run_scheduled` is a decision ladder over that state plus two conversation timestamps:

```python
def run_scheduled(self, run_obj, action):
    config = LeadQualificationConfig.from_raw(action.action_config)
    state = self.get_agent_state(run_obj)
    conversation = run_obj.conversation

    # exit conditions first - more on these below
    if self._should_exit_on_outbound(conversation, config, run_obj.started_at):
        return self._terminal(ScheduledRunStatus.EXITED_ON_OUTBOUND, state)
    if self._should_exit_on_messaging_window_closed(conversation):
        return self._terminal(ScheduledRunStatus.EXITED_ON_MESSAGING_WINDOW_CLOSED, state)
    if state.iterations >= config.max_iterations:
        return self._give_up(conversation, config, state)

    # has the lead said anything since I last looked?
    last_processed = parse_datetime(state.last_processed_at) if state.last_processed_at else None
    has_new_inbound = conversation.last_inbound_at is not None and (
        last_processed is None or conversation.last_inbound_at > last_processed)

    if has_new_inbound:
        # extract answers from the full conversation, reply, restart the nudge clock
        ...
        state.last_processed_at = conversation.last_inbound_at.isoformat()
        return self._reschedule(conversation, state, POLL_INTERVAL_SECONDS)

    next_nudge_at = parse_datetime(state.next_nudge_at) if state.next_nudge_at else None
    if next_nudge_at is not None and timezone.now() >= next_nudge_at:
        # the lead has gone quiet - nudge or give up
        ...

    return self._reschedule(conversation, state, POLL_INTERVAL_SECONDS)
```

Three outcomes, checked in order: new inbound since `last_processed_at`, so process and reply; no new inbound but a nudge is due, so nudge; otherwise reschedule and look again in five minutes.

The load-bearing comparison is `conversation.last_inbound_at > state.last_processed_at`. The agent never consumes messages or tracks message IDs; it tracks a high-water mark. When there is something new, it refetches the recent conversation window and hands the *whole transcript* to the LLM, then advances the mark. Ten new messages or one, same code path, one reply. The burst problem can't come back, because there is no code that handles "a message."

The shape also plays well with the engine's re-execution contract, though not perfectly: a re-run after a crash re-reads the same state and reaches the same decision, but if the crash landed between the WhatsApp send and the state write, the reply goes out twice. At-least-once, exactly as the last post warned; the poll shape shrinks the window, it doesn't close it.

## The race in the gap

There is a hole in the poll loop. The agent decides "nothing new, sleep five minutes" based on data read at the top of the run, but an agent turn takes real seconds (two LLM calls, a WhatsApp send). A lead who replies *during* the run has their message sitting there while the agent, having already made up its mind, schedules a five-minute nap. The debounce bump doesn't fully save you: the bump fires on the webhook, but `apply_result` writes the agent's returned `next_run_at` afterward, clobbering it.

So the reschedule path re-checks at the last moment:

```python
RECHECK_RESCHEDULE_SECONDS = 60
POLL_INTERVAL_SECONDS = 5 * 60

def _reschedule(self, conversation, state, delay_seconds):
    conversation.refresh_from_db(fields=['last_inbound_at'])
    last_processed = parse_datetime(state.last_processed_at) if state.last_processed_at else None
    if conversation.last_inbound_at is not None and (
            last_processed is None or conversation.last_inbound_at > last_processed):
        delay_seconds = RECHECK_RESCHEDULE_SECONDS
    return ScheduledRunResult(outcome=ScheduledRunOutcome.RESCHEDULE,
                              next_run_at=timezone.now() + timedelta(seconds=delay_seconds),
                              agent_state=state)
```

One `refresh_from_db` before sleeping: if a message slipped in mid-run, sleep 60 seconds instead of five minutes. Note what this deliberately doesn't do: it doesn't process the message right there. Processing mid-reschedule would mean a second LLM turn inside one wake-up and a second place in the code that handles new inbound. Instead the run ends normally and the *next* wake-up, one minute out, takes the normal path. The race isn't eliminated; it is made cheap. That is usually the better trade.

## Silence is a state, not an error

Half of lead qualification is what happens when the lead stops replying. Went to dinner? Comparing dealerships? Lost interest? The agent can't know, so the schedule has to encode a policy:

```python
# keeping nudge messages under 24 hours in total
DEFAULT_NUDGE_BACKOFF_SECONDS = [3600, 21600]   # 1h, then 6h
```

After each agent reply, the nudge clock restarts: `nudge_index` back to 0, `next_nudge_at` one hour out. If the lead stays silent past `next_nudge_at`, the poll's second branch sends a gentle check-in and advances the backoff. When the schedule is exhausted, the agent doesn't just vanish:

```python
def _give_up(self, conversation, config, state):
    state.gave_up = True
    self._finalize_answers(config, state)
    self._send_message(conversation, config.exit_message_on_giveup)
    return ScheduledRunResult(outcome=ScheduledRunOutcome.TERMINAL,
                              terminal_status=ScheduledRunStatus.COMPLETED,
                              agent_state=state)
```

It sends a configured goodbye ("Thanks for your time! Feel free to message us whenever you are ready."), finalizes whatever answers it did collect (a half-qualified lead is still a lead, and the salesperson gets the partial answers) and terminates with `gave_up` in its state so reporting can tell "qualified" from "gave up politely."

The backoff list is short and front-loaded on purpose, and the comment in the code says why: the whole silence policy fits inside 24 hours. That is not a product whim; it is the next section.

## The exit conditions are the product

The naive framing of this agent is "a loop that asks questions until they're answered." We spent more design time on the opposite: every way the loop must *stop*. They run at the top of every wake-up, before any LLM call, and each one earns its place:

**A human replied, so yield instantly.**

```python
def _should_exit_on_outbound(self, conversation, config, started_at):
    return bool(config.exit_on_outbound and conversation.last_outbound_at
                and conversation.last_outbound_at > started_at)
```

If the salesperson jumps into the chat, the worst thing the agent can do is keep talking over them. The check is the same trick as inbound detection, a conversation timestamp moving past a reference point. And it can't trip on the agent's own messages, thanks to a WhatsApp quirk worth knowing if you build on it: outbound webhooks fire only for messages sent from the actual phone app, not for API sends, while every inbound message arrives via webhook. So `last_outbound_at` moves only when a human speaks. This is the exit that makes the agent trustworthy enough to turn on: the human always wins, no toggle-hunting required.

**The messaging window closed, so we can't speak anyway.**

```python
def _should_exit_on_messaging_window_closed(self, conversation):
    return conversation.last_inbound_at is None or \
        timezone.now() - conversation.last_inbound_at > timedelta(hours=MESSAGING_WINDOW_HOURS)
```

WhatsApp only lets a business send free-form messages within 24 hours of the customer's last message. Outside that window every send needs a pre-approved template, which is the wrong tool for a chatty qualification flow. So a lead silent for 24 hours ends the run as `EXITED_ON_MESSAGING_WINDOW_CLOSED`, and now the nudge budget makes sense: first nudge after 1h, second after 6h more, give-up after a final 6h wait, roughly 13 hours worst case from the lead's last message. The whole silence policy finishes inside the window, so the polite give-up message is always still sendable. Platform constraint and product policy, encoded in the same two numbers.

**`max_iterations`, a cost ceiling.** Each iteration is LLM spend. A lead who chats forever without answering, or an edge case that loops, hits a hard cap and takes the give-up path. Nobody discovers a runaway agent on the monthly invoice.

**The lead says stop, so stop.** This one lives in the system prompt rather than the loop ("if the lead clearly declines to continue or asks you to stop messaging, acknowledge politely and stop asking questions") because recognizing "please stop texting me" in any language is exactly what the LLM is good at. Honest gap: the loop itself doesn't know the lead declined, so the run still drains through the nudge schedule before giving up. The clean fix is letting the extraction call set a disengage flag the loop can act on; it is on our list.

Notice that the exits reuse the engine's terminal statuses from the last post. `GROUP BY status` now answers the questions the business actually asks: how many conversations did the agent finish, how many did a human take over, how many leads went quiet. The exit conditions aren't defensive plumbing around the feature. For a tool a small business trusts with its leads, they *are* the feature.

## Closing: the $0 eval harness

Before this agent saw a real lead, its test rig was a subclass and a REPL:

```python
class TestLeadQualificationAction(LeadQualificationAction):
    def _fetch_conversation(self, conversation, window_start=None, limit=None):
        return list(self.simulated_conversation)

    def _send_message(self, conversation, message_text):
        self._append_simulated_message('sales-person', message_text)
        self.console.print(f"[bold red]sales-rep:[/bold red] {message_text}")
```

Override the two methods that touch the outside world (fetch conversation, send message) and the entire loop runs against an in-memory transcript with a simulated clock. `run_simulation()` drops you into a shell where *you type as the lead*, and after each turn it prints a `rich` table of the extraction state: every question, the current answer, the matched option, and the confidence in green or red against the threshold.

That table was the development loop. Type "budget wise maybe around 180k", watch the budget question flip green at 0.9. Type "btw discussed with my wife, we prefer the Corolla instead" and watch the model-question answer *change* and its confidence move. Type an email with a typo, then correct it, and watch the correction win. The class ships with a scripted lead for regression passes (greeting burst, questions back at the agent, a mid-conversation mind-change, a typo-and-correction) because those are the shapes that break naive extraction, and we wanted them two keystrokes away forever.

There is no assertion framework and no scoring here, and that is the point. Before you have any eval infrastructure, "watch the state table while you play the adversarial lead" catches most of the loop and prompt bugs you would otherwise meet in production, for the cost of a subclass. We built real evals later; the simulator is still what we reach for first when a prompt changes.

The loop, then: debounce the burst, poll the conversation, re-check before sleeping, nudge into silence with a deadline, and treat every exit as a designed outcome with a name. The LLM only ever gets called from inside that structure, and the next post is about keeping *it* honest: structured extraction, confidence thresholds, cost metering, and what leads type when they figure out they are talking to a model.
