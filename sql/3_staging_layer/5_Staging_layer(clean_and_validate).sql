USE DATABASE SPOTIFY_DB;

USE SCHEMA STAGING_LAYER;

select * from STG_ARTISTS;
-- STG ARTISTS [2]
CREATE OR REPLACE TABLE STG_ARTISTS AS
SELECT
    TRIM(ARTIST_ID)                         AS ARTIST_ID,
    TRIM(ARTIST_NAME)                       AS ARTIST_NAME,
    TRIM(EXTERNAL_URL)                      AS EXTERNAL_URL,

    -- Validation flag
    CASE
        WHEN ARTIST_ID IS NULL              THEN 'MISSING_ARTIST_ID'
        WHEN ARTIST_NAME IS NULL            THEN 'MISSING_NAME'
        ELSE 'VALID'
    END                                     AS DATA_QUALITY_FLAG,

    _LOAD_TIMESTAMP,
    CURRENT_TIMESTAMP()                     AS _TRANSFORM_TIMESTAMP
FROM RAW_LAYER.RAW_ARTISTS;

--TRY_TO_DATEA special version of the TO_DATE function that performs the same operation (i.e. converts an input expression to a date),but with error-handling support (i.e. if the conversion cannot be performed, it returns a NULL value instead of raising an error).
-- STG ALBUMS [3]
CREATE OR REPLACE TABLE STG_ALBUMS AS
SELECT
    TRIM(ALBUM_ID)                                      AS ALBUM_ID,
    TRIM(ALBUM_NAME)                                    AS ALBUM_NAME,
    TRY_TO_DATE(ALBUM_RELEASE_DATE, 'YYYY-MM-DD')       AS ALBUM_RELEASE_DATE,
    TRY_TO_NUMBER(ALBUM_TOTAL_TRACKS)                   AS ALBUM_TOTAL_TRACKS,
    TRIM(ALBUM_URL)                                     AS ALBUM_URL,

    -- Derived
    YEAR(TRY_TO_DATE(ALBUM_RELEASE_DATE, 'YYYY-MM-DD')) AS RELEASE_YEAR,

    -- Validation
    CASE
        WHEN ALBUM_ID IS NULL                           THEN 'MISSING_ALBUM_ID'
        WHEN TRY_TO_DATE(ALBUM_RELEASE_DATE) IS NULL    THEN 'INVALID_DATE'
        ELSE 'VALID'
    END                                                 AS DATA_QUALITY_FLAG,

    _LOAD_TIMESTAMP,
    CURRENT_TIMESTAMP()                                 AS _TRANSFORM_TIMESTAMP
FROM RAW_LAYER.RAW_ALBUMS;

-- STG SONGS [1]
CREATE OR REPLACE TABLE STG_SONGS AS
SELECT
    TRIM(SONG_ID)                                               AS SONG_ID,
    TRIM(SONG_NAME)                                             AS SONG_NAME,
    TRY_TO_NUMBER(SONG_DURATION)                                AS SONG_DURATION_MS,

    -- Convert ms to readable format
    FLOOR(TRY_TO_NUMBER(SONG_DURATION) / 60000)                 AS DURATION_MINUTES,
    ROUND((TRY_TO_NUMBER(SONG_DURATION) / 1000) - 
          (FLOOR(TRY_TO_NUMBER(SONG_DURATION) / 60000) * 60))   AS DURATION_SECONDS,

    TRIM(SONG_URL)                                              AS SONG_URL,
    TRY_TO_TIMESTAMP(SONG_ADDED)                                AS SONG_ADDED_TIMESTAMP,
    DATE(TRY_TO_TIMESTAMP(SONG_ADDED))                          AS SONG_ADDED_DATE,
    TRIM(ALBUM_ID)                                              AS ALBUM_ID,
    TRIM(ARTIST_ID)                                             AS ARTIST_ID,

    -- Validation flag
    CASE
        WHEN SONG_ID IS NULL                            THEN 'MISSING_SONG_ID'
        WHEN TRY_TO_NUMBER(SONG_DURATION) IS NULL       THEN 'INVALID_DURATION'
        WHEN TRY_TO_TIMESTAMP(SONG_ADDED)  IS NULL      THEN 'INVALID_DATE'
        WHEN ALBUM_ID IS NULL                           THEN 'MISSING_ALBUM_ID'
        WHEN ARTIST_ID IS NULL                          THEN 'MISSING_ARTIST_ID'
        ELSE 'VALID'
    END                                                         AS DATA_QUALITY_FLAG,

    _LOAD_TIMESTAMP,
    CURRENT_TIMESTAMP()                                         AS _TRANSFORM_TIMESTAMP
FROM RAW_LAYER.RAW_SONGS;

-- Quality summary across all tables
SELECT 'STG_SONGS'   AS TABLE_NAME, DATA_QUALITY_FLAG, COUNT(*) AS CNT FROM STAGING_LAYER.STG_SONGS   GROUP BY 1,2 UNION ALL
SELECT 'STG_ARTISTS' AS TABLE_NAME, DATA_QUALITY_FLAG, COUNT(*) AS CNT FROM STAGING_LAYER.STG_ARTISTS GROUP BY 1,2 UNION ALL
SELECT 'STG_ALBUMS'  AS TABLE_NAME, DATA_QUALITY_FLAG, COUNT(*) AS CNT FROM STAGING_LAYER.STG_ALBUMS  GROUP BY 1,2
ORDER BY TABLE_NAME, DATA_QUALITY_FLAG;