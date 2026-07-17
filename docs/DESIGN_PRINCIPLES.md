# Design Principles

This document describes the design decisions and architectural principles followed in building the Spotify ETL pipeline.

## 1. Medallion Architecture (Bronze → Silver → Gold)

The pipeline follows a three-layer medallion architecture:

| Layer | Schema | Purpose | Data Quality |
|-------|--------|---------|--------------|
| Bronze (Raw) | `RAW_LAYER` | Land data as-is from source | Untransformed, all VARCHAR |
| Silver (Staging) | `STAGING_LAYER` | Cleanse, validate, type-cast | Quality-flagged, typed |
| Gold (Warehouse) | `WAREHOUSE_LAYER` | Business-ready star schema | SCD2 dimensions, facts |

**Why**: Separating layers ensures each stage has a single responsibility. Raw preserves source fidelity, staging handles data quality, warehouse delivers analytics-ready models.

## 2. SCD Type 2 (Slowly Changing Dimensions)

Dimension tables (`DIM_ARTISTS`, `DIM_ALBUMS`) use SCD Type 2 to preserve historical changes:

- **EFF_START_DATE**: When the record version became active (`CURRENT_DATE()`)
- **EFF_END_DATE**: When it was superseded (`CURRENT_DATE() - 1`) — non-overlapping ranges
- **IS_CURRENT**: Boolean flag for easy filtering of current records

**Why**: Business users need to query both current state AND historical changes. SCD2 enables "as-of" reporting without losing previous values.

**Limitation**: Snowflake MERGE cannot both UPDATE (close) and INSERT (new version) for the same business key in one pass. We use MERGE + separate INSERT (2 statements minimum).

## 3. Append-Only Streams for CDC

Streams are configured as `APPEND_ONLY = TRUE` on raw tables.

**Why**:
- Raw tables only receive INSERTs from Snowpipe (no updates/deletes at source)
- Append-only streams ignore UPDATE operations — this prevents the **feedback loop** where `UPDATE SET LOAD_STATUS = 'LOADED'` would be captured by a standard stream, re-triggering the task indefinitely
- More efficient than standard streams (less metadata overhead)

## 4. LOAD_STATUS Audit Column

Raw tables have a `LOAD_STATUS` column (`DEFAULT 'NEW'`) that transitions:

```
Pipe loads record → 'NEW' (from DEFAULT)
Task processes it → 'LOADED' (UPDATE after MERGE)
```

**Why**: Provides visibility into which records have been processed. Used by the guarded DELETE to identify the "current snapshot" for stale record detection. Not used for CDC (streams handle that).

**Compatibility with Streams**: Since streams are append-only, the UPDATE to LOAD_STATUS is invisible to them — no feedback loop.

## 5. Empty-Set Guardrail on DELETE

Every DELETE statement that removes stale records from staging includes a guard:

```sql
DELETE FROM STAGING_LAYER.STG_SONGS
WHERE (SELECT COUNT(*) FROM RAW_LAYER.RAW_SONGS WHERE LOAD_STATUS = 'NEW') > 0
AND SONG_ID NOT IN (
    SELECT TRIM(SONG_ID) FROM RAW_LAYER.RAW_SONGS WHERE LOAD_STATUS = 'NEW'
);
```

**Why**: Without the guard, `NOT IN (empty subquery)` evaluates to TRUE for all rows — accidentally wiping the entire staging table when no new data has been loaded. This was discovered after a production incident where STG_ALBUMS was emptied.

## 6. Soft Delete on Fact Table

The fact table uses `IS_VALID BOOLEAN DEFAULT TRUE` instead of hard deletes:

- Songs removed from source: `IS_VALID = FALSE`
- Songs that reappear: `IS_VALID = TRUE` (re-validated)

**Why**: Preserves historical record of what existed. Analytics queries filter `WHERE IS_VALID = TRUE` for current state. No data is permanently lost.

## 7. MERGE-Based Idempotent Loading

Every layer uses MERGE (not INSERT) for data loading:

- **Staging**: MERGE on business key (SONG_ID, ARTIST_ID, ALBUM_ID) — insert new, update changed
- **Dimensions**: MERGE to close changed/deleted records + INSERT for new versions
- **Facts**: MERGE on SONG_ID — insert new, update if attributes changed

**Why**: MERGE is idempotent — re-running the same data produces the same result. This is critical for:
- Task retries after failures
- Duplicate data from Snowpipe (same file loaded multiple times)
- Recovery without manual intervention

## 8. Task DAG Orchestration

Tasks are organized as a Directed Acyclic Graph (DAG):

```
Root (CRON trigger) → Staging tasks (parallel) → Dimension tasks → Fact task
```

**Design rules**:
- Root task must be SUSPENDED before modifying child tasks
- Children RESUME before root (bottom-up)
- `WHEN SYSTEM$STREAM_HAS_DATA(...)` prevents unnecessary execution
- `SUSPEND_TASK_AFTER_NUM_FAILURES` auto-disables broken tasks

## 9. Snowpipe Without Event Grid

Azure auto-ingest pipes require Event Grid notifications, which needs Azure portal access. Since organizational restrictions prevented this, we use:

- Pipes with `AUTO_INGEST = FALSE`
- A task DAG that runs `ALTER PIPE ... REFRESH` every 5 minutes

**Trade-off**: Slightly higher latency (up to 5 minutes) vs. true real-time auto-ingest. But works without any Azure portal configuration beyond the SAS token.

**Important**: Snowpipe deduplicates by filename (14-day window). Source files must have unique names (timestamped).

## 10. ETL Audit Logging

Every task logs execution details to `ETL_AUDIT_LOG`:

- Pipeline run ID (correlates tasks in same cycle)
- Row counts (inserted, updated, deleted)
- Timing (start, end, duration)
- Status (SUCCESS/FAILED)

**Why**: Single source of truth for pipeline observability. Complements Snowflake's built-in `TASK_HISTORY` with business-level metrics (row counts, which table was affected).

## 11. Dynamic Tables for Analytics

Auto-refreshing materialized views (`TARGET_LAG = '1 hour'`) that join fact + dimensions:

- `SPOTIFY_SONGS_ENRICHED`: Denormalized song details
- `ARTIST_SUMMARY`: Aggregated artist metrics

**Why**: Downstream consumers (dashboards, reports) get pre-joined, always-fresh data without running complex queries. Snowflake handles incremental refresh automatically.

## 12. Data Quality at Source

Staging layer applies quality checks and flags records:

```sql
CASE
    WHEN SONG_ID IS NULL THEN 'MISSING_SONG_ID'
    WHEN TRY_TO_NUMBER(SONG_DURATION) IS NULL THEN 'INVALID_DURATION'
    ELSE 'VALID'
END AS DATA_QUALITY_FLAG
```

Only `DATA_QUALITY_FLAG = 'VALID'` records flow to the warehouse layer. Invalid records are retained in staging for investigation but don't pollute analytics.

## 13. Non-Overlapping Date Ranges

For SCD2 dimensions:
- Old record ends: `EFF_END_DATE = CURRENT_DATE() - 1`
- New record starts: `EFF_START_DATE = CURRENT_DATE()`

**Why**: Ensures a date lookup (e.g., "what was the artist name on July 10?") returns exactly one record, never two. Standard practice for temporal data modeling.

## 14. Timezone Consistency

- Account/session timezone: `Europe/Berlin`
- Task CRON schedule: `*/5 * * * * Europe/Berlin`
- Timestamps stored as `TIMESTAMP_NTZ` (no timezone embedded — relies on session setting for display)

**Why**: Single timezone eliminates confusion when correlating audit logs, task history, and business timestamps.

## 15. Explicit Transaction Control (All-or-Nothing)

Every task wraps its DML statements in an explicit transaction with exception handling:

```sql
BEGIN
    LET v_start TIMESTAMP_NTZ := CURRENT_TIMESTAMP();
    -- variable declarations ...

    BEGIN TRANSACTION;

    -- All DML: MERGE, DELETE, UPDATE, INSERT audit log

    COMMIT;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
```

**Why**: Without explicit transactions, Snowflake SQL scripting auto-commits each DML independently. If a later statement fails (e.g., the audit INSERT), earlier statements (MERGE, DELETE, UPDATE) remain committed — leaving the pipeline in a partial/inconsistent state. Explicit transactions ensure:
- On success: all changes commit atomically
- On failure: all changes roll back, stream offset is NOT advanced, and the task retries cleanly next cycle

**Stream interaction**: A stream's offset advances only at COMMIT. On ROLLBACK, the offset stays unchanged — the same change records remain available for the next execution. This is the key mechanism that makes retry safe.

## 16. INSERT ... SELECT Over INSERT ... VALUES for Expressions

Audit log inserts use `INSERT INTO ... SELECT` instead of `INSERT INTO ... VALUES`:

```sql
-- Correct: evaluated as an expression
INSERT INTO ETL_AUDIT_LOG (...)
SELECT :v_run_id, ..., DATEDIFF('second', :v_start, CURRENT_TIMESTAMP());

-- Incorrect: fails in scripting context
INSERT INTO ETL_AUDIT_LOG (...)
VALUES (:v_run_id, ..., DATEDIFF('second', :v_start, CURRENT_TIMESTAMP()));
```

**Why**: Snowflake's SQL scripting engine cannot evaluate complex expressions (like `DATEDIFF` with variables) inside a `VALUES` clause. It attempts to interpret them as literals, producing a "Invalid expression" compilation error. Using `SELECT` forces proper expression evaluation.
