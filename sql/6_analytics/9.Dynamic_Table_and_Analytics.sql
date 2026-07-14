-- Dynamic tables for auto-refreshing Spotify analytics using current/valid records
-- Co-authored with CoCo
-- ================================================
-- DYNAMIC TABLE - Auto-refreshing analytics
-- ================================================
USE SPOTIFY_DB;
USE SCHEMA WAREHOUSE_LAYER;

-- Songs enriched with artist and album details
CREATE OR REPLACE DYNAMIC TABLE SPOTIFY_SONGS_ENRICHED
    TARGET_LAG = '1 hour'
    WAREHOUSE = SPOTIFY_ETL_WH
AS
SELECT
    f.SONG_ID,
    f.SONG_NAME,
    f.DURATION_MINUTES || ':' || 
        LPAD(f.DURATION_SECONDS::VARCHAR, 2, '0')   AS SONG_DURATION_FORMATTED,
    f.SONG_DURATION_MS,
    f.SONG_ADDED_DATE,
    f.SONG_URL,
    a.ARTIST_NAME,
    a.EXTERNAL_URL                                   AS ARTIST_URL,
    al.ALBUM_NAME,
    al.ALBUM_RELEASE_DATE,
    al.ALBUM_TOTAL_TRACKS,
    al.RELEASE_YEAR,
    al.ALBUM_URL
FROM FACT_SONGS f
JOIN DIM_ARTISTS a  ON f.ARTIST_SK = a.ARTIST_SK AND a.IS_CURRENT = TRUE
JOIN DIM_ALBUMS  al ON f.ALBUM_SK  = al.ALBUM_SK AND al.IS_CURRENT = TRUE
WHERE f.IS_VALID = TRUE;

-- Artist summary dynamic table
CREATE OR REPLACE DYNAMIC TABLE ARTIST_SUMMARY
    TARGET_LAG = '1 hour'
    WAREHOUSE = SPOTIFY_ETL_WH
AS
SELECT
    a.ARTIST_NAME,
    COUNT(DISTINCT f.SONG_ID)               AS TOTAL_SONGS,
    COUNT(DISTINCT f.ALBUM_SK)              AS TOTAL_ALBUMS,
    ROUND(AVG(f.SONG_DURATION_MS)/1000, 0)  AS AVG_SONG_DURATION_SEC,
    MIN(al.ALBUM_RELEASE_DATE)              AS EARLIEST_ALBUM,
    MAX(al.ALBUM_RELEASE_DATE)              AS LATEST_ALBUM,
    SUM(al.ALBUM_TOTAL_TRACKS)              AS TOTAL_TRACKS_ACROSS_ALBUMS
FROM FACT_SONGS f
JOIN DIM_ARTISTS a  ON f.ARTIST_SK = a.ARTIST_SK AND a.IS_CURRENT = TRUE
JOIN DIM_ALBUMS  al ON f.ALBUM_SK  = al.ALBUM_SK AND al.IS_CURRENT = TRUE
WHERE f.IS_VALID = TRUE
GROUP BY a.ARTIST_NAME;