---
title: "RDS PostgreSQL 13 to 15 Upgrade with GCP DataStream"
date: 2025-04-20T00:00:00+08:00
draft: false
description: "A practical guide to upgrading RDS PostgreSQL 13 to 15 when logical replication and GCP DataStream are in the picture -- checklist, gotchas, and post-upgrade steps."
tags: [postgresql, rds, aws, datastream, gcp, devops, database, upgrade, cdc]
---

We upgraded our AWS RDS PostgreSQL instance from version 13 to 15. On paper it looks like a few clicks in the console. In practice, with logical replication and a CDC pipeline involved, there are several things that will block or break the upgrade if you do not handle them in the right order.

## Context

- RDS instance: db.m5.4xlarge, ~1.5TB database, primary + read-replica
- ~5000 API requests/min at peak load
- GCP DataStream connected to BigQuery via logical replication -- this is the main complication
- Custom parameter group on both primary and read-replica with logical replication enabled
- No blue-green deployment on AWS RDS, so this is an in-place upgrade with real downtime
- BigQuery will show roughly 1 hour of data loss for the period the slot was dropped -- DataStream cannot backfill that gap automatically. AWS does offer a manual backfill option but it has additional cost associated with it

Because there is no blue-green option here, the ~8 minutes of downtime is real and users will see it. Planning matters.

### Finding the maintenance window

Query your ALB access logs in Athena. Group by hour and day of week, find the window with the lowest request volume. That is your target. Get it formally approved before you start planning the production upgrade.

### Test in dev or QA first

Run the full upgrade procedure in a dev or QA environment before touching production. If you do not have a dedicated QA environment, let the upgraded instance run there for a couple of days under real usage before you plan the production date.

---

## Pre-Upgrade Checklist

Run these before anything else. They are read-only and safe at any time.

### 1. Note your custom parameter group values

In the RDS Console, open your parameter group and filter by `Source = modified`. Sort by source -- the modified values float to the top and are easy to copy down. You will need to recreate these in a new parameter group after the upgrade.

You can also do this via CLI:

```bash
aws rds describe-db-parameters \
  --db-parameter-group-name <your-param-group> \
  --source modified \
  --query 'Parameters[*].{Name:ParameterName,Value:ParameterValue}' \
  --output table
```

### 2. Check current PostgreSQL version

```sql
SHOW server_version;
```

### 3. Check for replication slots

```sql
SELECT slot_name FROM pg_replication_slots;
```

Replication slots must be dropped before the upgrade starts. If any exist, the upgrade will fail. Note the slot names -- you will need to recreate them after.

### 4. Check the precheck log

RDS Console -> your instance -> Logs & events -> `upgrade-prechecks.log`

This log shows exactly what will block the upgrade. Check it before you trigger anything.

---

## Prepare the New Parameter Group

Do this before pausing DataStream.

The old parameter group (family `postgres13`) is not compatible with PG15. Create a new parameter group with family `postgres15` and carry over your custom values from what you noted above.

In my setup the params I needed to carry over were `rds.logical_replication=1`, `wal_keep_size`, and `work_mem`. Your list will be different -- use what you captured in the checklist above.

---

## Pause DataStream and Drop the Replication Slot

### Pause DataStream first

In GCP, pause the DataStream. Wait until the status shows **Paused** -- not "Draining". Draining means it is still flushing in-flight data. Do not proceed until the status is fully Paused.

### Drop the replication slot

You need the `rds_replication` role to do this. Your regular application DB user (the one Django uses via `dbshell`) likely does not have this permission -- use a superuser or an admin user that has it, or grant it explicitly first.

```sql
GRANT rds_replication TO your_username;

SELECT pg_drop_replication_slot('your_slot_name');

-- Confirm it is gone
SELECT * FROM pg_replication_slots;
```

If you skip this step, the upgrade will fail with:

> "The instance could not be upgraded because it has one or more logical replication slots."

The precheck log in RDS Console will also call this out explicitly.

---

## Trigger the Upgrade

Take a manual RDS snapshot before starting.

Then: RDS Console -> Modify -> Engine version -> PostgreSQL 15.x -> Apply immediately.

### What the timeline actually looks like (1.5TB instance)

- The read-replica enters the upgrade process first and becomes unavailable
- Pre-upgrade snapshot: approximately 1 hour
- Actual upgrade: approximately 10 minutes
- True downtime where the DB is unreachable: approximately 8 minutes
- The read-replica becomes available before the primary is back

Those 8 minutes are the window where users will see errors in the application. This is why the maintenance window needs to land in your lowest traffic slot.

---

## Apply the New Parameter Group

Once the primary is back and shows Available, apply the new `postgres15` parameter group you created earlier.

`rds.logical_replication` is a static parameter -- it will not take effect until the instance is rebooted. Apply the param group and reboot.

After the reboot, verify in RDS Console that the instance shows the correct parameter group and its status is in-sync. If it still shows the old group or is out-of-sync, do not proceed.

---

## Recreate the Replication Slot and Resume DataStream

Same permission requirement as dropping -- your regular Django DB user will not be able to run this. Use the same admin user you used earlier.

```sql
SELECT pg_create_logical_replication_slot('your_slot_name', 'pgoutput');

-- Confirm
SELECT slot_name FROM pg_replication_slots;
```

Once the slot is confirmed, go to GCP and resume DataStream. Wait for the status to show **Running** before moving on.

---

## Run VACUUM ANALYZE

This step is not optional.

`pg_upgrade` resets all query planner statistics. Without them, the planner has no idea about table sizes, row counts, or data distribution. It will make bad execution plan choices and queries will be slow.

```sql
VACUUM ANALYZE;
```

A few things to know:

- It is non-blocking and safe to run on live production
- On a large database it will take many hours
- Queries improve progressively as each table is analyzed -- you do not have to wait until the end for things to get better
- Safe to interrupt and rerun at any time
- Do NOT run it on the read-replica separately -- the effects replicate automatically from the primary

### Monitor progress

```sql
SELECT relid::regclass, phase, heap_blks_scanned, heap_blks_total
FROM pg_stat_progress_vacuum;
```

### Warning you will see and can ignore

```
WARNING: skipping "pg_stat_statements" --- only table or database owner can vacuum it
```

These are RDS-owned system tables. Your application tables are not affected.

### What to expect during vacuum

While vacuum is running, APIs will respond slowly and your Celery workers will be slower too. Queues will fill up and stay backed up until vacuum finishes. Just wait it out -- there is nothing to fix here. Once vacuum completes, verify the application and run a smoke test before calling the upgrade done.

---

## Order of Operations

A clean reference for the day of the upgrade:

1. Identify maintenance window using ALB logs in Athena
2. Get the window approved
3. Run the full upgrade in dev or QA first, let it soak for a couple of days
4. Create the new `postgres15` parameter group with your custom params
5. Take a manual RDS snapshot
6. Pause DataStream, wait for status: Paused
7. Drop the replication slot, confirm it is gone
8. Trigger the upgrade: Modify -> PostgreSQL 15.x -> Apply immediately
9. Read-replica upgrades first, then primary -- expect ~8 minutes of true downtime
10. Apply the new parameter group to primary, reboot
11. Verify parameter group is in-sync in RDS Console
12. Recreate the replication slot
13. Resume DataStream, wait for status: Running
14. Run `VACUUM ANALYZE`
15. Monitor progress via `pg_stat_progress_vacuum`, then smoke test
