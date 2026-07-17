# Spotify ETL Pipeline on Snowflake

End-to-end data pipeline that ingests Spotify data from Azure Blob Storage into a Snowflake data warehouse using a medallion architecture (Raw → Staging → Warehouse) with automated CDC, SCD Type 2 dimensions, and real-time analytics.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        AZURE BLOB STORAGE                           │
│  spotify-transformed-data/                                          │
│    ├── song_data/   (full snapshot CSV)                             │
│    ├── artist_data/ (full snapshot CSV)                             │
│    └── album_data/  (full snapshot CSV)                             │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ SAS Token Authentication
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│  RAW_LAYER (Landing Zone)                                           │
│  ┌────────────┐  ┌─────────────┐  ┌────────────┐                   │
│  │ RAW_SONGS  │  │ RAW_ARTISTS │  │ RAW_ALBUMS │                   │
│  │ +LOAD_STATUS│  │ +LOAD_STATUS│  │ +LOAD_STATUS│                  │
│  └─────┬──────┘  └──────┬──────┘  └──────┬─────┘                   │
│        │ Append-only     │ Append-only     │ Append-only             │
│        │ Streams         │ Streams         │ Streams                 │
│  Snowpipe + Task-driven refresh (every 5 min)                       │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ MERGE (insert/update) + Guarded DELETE
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│  STAGING_LAYER (Cleansed & Validated)                               │
│  ┌────────────┐  ┌─────────────┐  ┌────────────┐                   │
│  │ STG_SONGS  │  │ STG_ARTISTS │  │ STG_ALBUMS │                   │
│  │ +QUALITY   │  │ +QUALITY    │  │ +QUALITY   │                   │
│  └─────┬──────┘  └──────┬──────┘  └──────┬─────┘                   │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ SCD Type 2 MERGE + Fact MERGE
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│  WAREHOUSE_LAYER (Star Schema)                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │ DIM_ARTISTS  │  │ DIM_ALBUMS   │  │ FACT_SONGS   │              │
│  │ (SCD Type 2) │  │ (SCD Type 2) │  │ (+IS_VALID)  │              │
│  └──────────────┘  └──────────────┘  └──────────────┘              │
│                                                                      │
│  Dynamic Tables: SPOTIFY_SONGS_ENRICHED, ARTIST_SUMMARY             │
└─────────────────────────────────────────────────────────────────────┘
```

## Task DAG (Orchestration)

```
TASK_REFRESH_PIPE_SONGS (5 min)     TASK_ROOT_SPOTIFY_PIPELINE (CRON */5 Europe/Berlin)
    → TASK_REFRESH_PIPE_ARTISTS         → TASK_LOAD_STAGING_SONGS
        → TASK_REFRESH_PIPE_ALBUMS      → TASK_LOAD_STAGING_ARTISTS
                                        → TASK_LOAD_STAGING_ALBUMS
                                            → TASK_LOAD_DIMENSIONS_ARTISTS
                                            → TASK_LOAD_DIMENSIONS_ALBUMS
                                                → TASK_LOAD_FACTS
```

## Folder Structure

```
sql/
├── 1_setup/                    # Database, schemas, warehouses, file formats
├── 2_raw_layer/                # External stages, raw tables, pipes, pipe refresh tasks
├── 3_staging_layer/            # Staging tables with cleansing & validation
├── 4_warehouse_layer/          # Dimension tables (SCD2), fact table, initial loads
├── 5_pipeline/                 # Streams, tasks with CDC, audit logging
├── 6_analytics/                # Dynamic tables, sample queries
└── 7_utilities/                # Ad-hoc queries, cleanup scripts
docs/
└── DESIGN_PRINCIPLES.md        # Detailed design decisions
```

## Deployment Order

Run SQL files in this sequence:

1. `sql/1_setup/1_Snowflake Initial Configuration.sql` — Create database, schemas, warehouses
2. `sql/1_setup/Azure_blob_storage.sql` — Reference for Azure blob config
3. `sql/2_raw_layer/3_Azure_External_Stages.sql` — Create external stages with SAS token
4. `sql/2_raw_layer/4_Create_tables_and_load_data.sql` — Create raw tables, initial COPY INTO
5. `sql/2_raw_layer/8.Snowpipe_Auto_Ingest.sql` — Create pipes, LOAD_STATUS column, pipe refresh tasks, ETL audit log
6. `sql/3_staging_layer/5_Staging_layer(clean_and_validate).sql` — Create staging tables
7. `sql/4_warehouse_layer/6_Warehouse_layer(Final_Analytics_Tables).sql` — Create dimension & fact tables
8. `sql/5_pipeline/7_Automated_Pipeline(Streams+Tasks).sql` — Create streams, all tasks with audit logging
9. `sql/6_analytics/9.Dynamic_Table_and_Analytics.sql` — Create dynamic tables

## Prerequisites

- **Snowflake Account** with ACCOUNTADMIN role
- **Azure Blob Storage** container with Spotify CSV data
- **SAS Token** for Azure stage authentication
- **Warehouses**: `COMPUTE_WH` (general), `SPOTIFY_ETL_WH` (pipeline tasks)

## Azure Setup

1. Create Azure Storage Account with a container (e.g., `spotify-transformed-data`)
2. Create subfolders: `song_data/`, `artist_data/`, `album_data/`
3. Generate a SAS token with Read, List permissions
4. Upload CSV files with unique timestamped filenames (e.g., `song_transformed_2026-07-14 09:19:46.csv`)

## Key Configuration

- **Timezone**: `Europe/Berlin` (account-level or task CRON)
- **Task schedule**: Every 5 minutes
- **Dynamic table refresh**: 1 hour target lag
- **Stream type**: Append-only (avoids feedback loops with LOAD_STATUS updates)

## Monitoring

```sql
-- ETL Audit Log (custom)
SELECT * FROM RAW_LAYER.ETL_AUDIT_LOG ORDER BY CREATED_AT DESC;

-- Pipeline summary view
SELECT * FROM RAW_LAYER.V_ETL_PIPELINE_SUMMARY;

-- Snowflake task history (built-in)
SELECT * FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('day', -1, CURRENT_TIMESTAMP())
)) ORDER BY SCHEDULED_TIME DESC;

-- Pipe status
SELECT SYSTEM$PIPE_STATUS('RAW_LAYER.PIPE_SONGS');
```

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| "root task is not suspended" | Trying to modify DAG while root is active | Run `ALTER TASK TASK_ROOT_SPOTIFY_PIPELINE SUSPEND;` first |
| "Duplicate row detected" in MERGE | Multiple IS_CURRENT=TRUE records for same ID in DIM tables | Deduplicate: keep MAX(SK) per ID, delete others |
| Stream empty after data load | Stream was recreated AFTER data was loaded | Trigger a new file load (stream only captures future inserts) |
| Staging wiped (0 rows) | DELETE ran with empty LOAD_STATUS='NEW' subquery | Guard clause: `WHERE (SELECT COUNT(*) ... WHERE LOAD_STATUS='NEW') > 0` |
| Pipe skips file | Same filename as previously loaded (14-day dedup) | Use unique timestamped filenames |
| "ambiguous column name" on ADD COLUMN IF NOT EXISTS | Column already exists | Comment out the ALTER TABLE statement |
| Task suspended due to errors | Snowflake auto-suspends after repeated failures | Fix root cause, then `ALTER TASK ... RESUME;` |
| "Invalid expression [DATE_DIFF...]" in VALUES clause | Snowflake scripting can't evaluate DATEDIFF inside VALUES | Use `INSERT INTO ... SELECT` instead of `INSERT INTO ... VALUES` |
| Partial data after task failure | DML auto-commits without explicit transaction | Wrap all DML in `BEGIN TRANSACTION ... COMMIT` with `EXCEPTION WHEN OTHER THEN ROLLBACK` |
