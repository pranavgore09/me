---
title: "Diagnosing PostgreSQL Connection Leaks on RDS"
date: 2026-03-16T19:37:39+08:00
draft: false
description: "How a Gunicorn and PostgreSQL statement_timeout mismatch caused orphaned RDS connections, 502 errors under load, and how to find and fix it using pg_stat_activity."
tags: [postgresql, rds, django, gunicorn, backend, devops, aws, performance, connection-leak]
---

The site started throwing 502 Bad Gateway errors. Everything stopped. Restarting Gunicorn fixed it within seconds. Then it would happen again, at a completely random time, once every few days. This went on for about two weeks before we decided to properly dig in.

That pattern is almost always a leak. In our case it was database connections.

## Infrastructure context

- RDS: `db.m5.4xlarge`, `max_connections=5000`, `tcp_keepalives_idle=300s`
- Gunicorn: 8 workers x 25 threads = 200 concurrent connections
- Celery: 3 instances (1 main worker at concurrency=35, 2 side workers at concurrency=25 each) = 85 worker threads total
- Total max DB connections across all processes: 285

Peak traffic (8am to 8pm SGT):

- ~4000 ALB requests/min
- ~2100 Celery tasks/min, ~2100 DB queries/min
- Total DB load: ~6100 queries/min (~102/sec)

At 102 queries/sec across 285 workers, each worker handles one query roughly every 2.8 seconds. That is healthy if the queries are fast. Some were not, and we had to find those the hard way because everything worked well for the first year after the features shipped.

## Step 1: Count connections by source

Start here. Group `pg_stat_activity` by client IP and state.

```sql
SELECT
    client_addr,
    usename,
    application_name,
    state,
    COUNT(*) AS connection_count,
    MAX(now() - state_change) AS longest_in_state
FROM pg_stat_activity
WHERE pid <> pg_backend_pid()
GROUP BY client_addr, usename, application_name, state
ORDER BY connection_count DESC;
```

We saw our API server IP with dozens of connections in `idle` state, some sitting there for 3 to 5 minutes. These were not connections waiting for the next request. They were connections that Gunicorn workers had abandoned mid query, but the database did not know that yet. The DB side still held them open.

## Step 2: Drill into the specific server

```sql
SELECT
    state,
    wait_event_type,
    wait_event,
    COUNT(*) as cnt
FROM pg_stat_activity
WHERE client_addr = '<api-server-ip>'
GROUP BY state, wait_event_type, wait_event
ORDER BY cnt DESC;
```

## Step 3: Find long running queries

```sql
SELECT
    pid,
    state,
    backend_type,
    now() - pg_stat_activity.query_start AS duration,
    query::varchar
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '5 seconds'
ORDER BY duration DESC;
```

Queries running for 30, 60, sometimes over 100 seconds. On an API that is supposed to respond in under a second.

## Step 4: Separate root causes from victims

Not every slow query is a root cause. Some are just waiting on a lock held by someone else.

Slow queries not blocked by anyone (the actual culprits):

```sql
SELECT
    pid,
    state,
    now() - query_start AS duration,
    wait_event_type,
    wait_event,
    query::varchar
FROM pg_stat_activity
WHERE state != 'idle'
AND cardinality(pg_blocking_pids(pid)) = 0
ORDER BY duration DESC;
```

Queries blocked by someone else (the victims):

```sql
SELECT
    pid,
    state,
    now() - query_start AS duration,
    wait_event_type,
    wait_event,
    query::varchar,
    pg_blocking_pids(pid) AS blocked_by
FROM pg_stat_activity
WHERE state != 'idle'
AND cardinality(pg_blocking_pids(pid)) > 0
ORDER BY duration DESC;
```

Fix the first group. The second group resolves on its own.

## The slow queries (from pg_stat_statements)

Stats accumulated since the last reset, so call counts are cumulative over years. What matters is the average duration.

| Query pattern | Avg duration |
|---|---|
| SELECT COUNT(DISTINCT ...) on organization join | 6900ms |
| SELECT on product collection with user join | 6800ms |
| SELECT on dashboard client data | 6300ms |
| SELECT DISTINCT on organization | 5300ms |
| SELECT DISTINCT on document templates (4 variants) | 1700 to 2000ms |

These are analytics style queries: `COUNT(DISTINCT ...)`, `SELECT DISTINCT` on large tables. Expensive by nature. And they were sitting on the synchronous request path.

## Root cause: timeout mismatch

Gunicorn has a worker timeout. Default is 30 seconds. If a worker takes longer than that, Gunicorn force kills the process.

We had PostgreSQL `statement_timeout` set to 300 seconds.

When Gunicorn force kills a worker at 30 seconds:

1. The OS process is killed, no graceful shutdown
2. The database connection is not closed cleanly
3. The query keeps running in PostgreSQL for up to 300 more seconds
4. PostgreSQL does not know the client is gone until TCP keepalive fires
5. With `tcp_keepalives_idle=300s`, that detection takes up to 5 minutes

Result: orphaned connections accumulate faster than keepalive cleans them. Under load with multiple slow queries in flight simultaneously, all 200 Gunicorn threads eventually get stuck. New requests queue up, timeout at the load balancer, and the ALB returns 502 to the user.

Restarting Gunicorn closes all OS sockets. RDS detects the TCP drop immediately and frees all connections. That is why the restart worked.

## The fix

Set `statement_timeout` to fire before Gunicorn kills the worker. Gunicorn default is 30s, so 25s gives a clean margin.

The cleanest way to do this in Django is via database connection options in settings:

```python
DATABASES = {
    'default': {
        # ... other config
        'OPTIONS': {
            'options': f'-c statement_timeout={DEFAULT_DB_QUERY_TIMEOUT_IN_MS}',
        }
    }
}
```

This applies the timeout to every connection this Django process opens. No changes needed in RDS or PostgreSQL config.

Alternatively, set it at the PostgreSQL level:

```sql
ALTER SYSTEM SET statement_timeout = '25000';
SELECT pg_reload_conf();
```

Or in your RDS parameter group: set `statement_timeout = 25000` (value is in milliseconds).

For specific endpoints you know are slow, override per request while you fix the underlying query:

```python
with connection.cursor() as cursor:
    cursor.execute("SET LOCAL statement_timeout = '60000'")
    # run the slow query
```

`SET LOCAL` scopes the timeout to the current transaction only.

When PostgreSQL cancels a query at 25s, the application gets a clean error and the connection is returned to the pool. No orphan.

## Improving the slow queries

Fixing the timeout alignment stops the bleeding. The next step is fixing the queries themselves.

We iterated over each offending query: reviewing the query structure, checking execution plans with `EXPLAIN ANALYZE`, adding indexes where they were missing, and using partial counts where the product allowed approximate results. Some queries could be restructured to avoid `COUNT(DISTINCT ...)` entirely; others just needed the right composite index.

Query performance improvement is its own topic and not covered here, but that work is what makes the timeout fix permanent rather than a safeguard you keep leaning on.

Long term: move slow queries off the request path entirely. Return 202 immediately, run in Celery, let the client poll for the result. No request should hold a DB connection open for more than a second or two.

## Kill connections during an incident

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '100 seconds';
```

This terminates active connections mid query, which surfaces errors to users. Use it when connections are piling up and you need breathing room.

To target a specific server only:

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE client_addr = '<api-server-ip>'
AND state = 'idle'
AND (now() - state_change) > interval '2 minutes';
```

## Conclusion

We had roughly 300 connections on a database that supports 5000, and it was still going down. The problem was never the connection count. It was that workers were getting stuck and abandoning connections, which then piled up faster than the database could detect and clean them. Once the timeout alignment was in place and the slow queries were improved, the restarts stopped and the 502s disappeared. The lesson was straightforward: any feature that works fine under normal load for a year can quietly become a problem once traffic grows enough to expose the edge cases in query performance. Keeping `statement_timeout` set deliberately, and keeping an eye on `pg_stat_statements` periodically, makes those problems visible before they become incidents.
