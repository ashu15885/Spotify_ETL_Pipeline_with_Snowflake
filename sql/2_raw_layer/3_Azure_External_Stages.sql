USE ROLE SPOTIFY_ETL_ROLE;
USE DATABASE SPOTIFY_DB;
USE SCHEMA RAW_LAYER;
USE WAREHOUSE SPOTIFY_ETL_WH;

CREATE OR REPLACE FILE FORMAT SPOTIFY_CSV_FORMAT
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    RECORD_DELIMITER = '\n'
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('NULL', 'null', 'N/A', '')
    EMPTY_FIELD_AS_NULL = TRUE
    DATE_FORMAT = 'AUTO'
    TIMESTAMP_FORMAT = 'AUTO';

-- Stage for album_data folder [3]
CREATE OR REPLACE STAGE STAGE_ALBUMS
    --STORAGE_INTEGRATION = AZURE_SPOTIFY_INTEGRATION
    URL = 'azure://spotifyetlstorageashu.blob.core.windows.net/spotify-transformed-data/album_data/'
    FILE_FORMAT = SPOTIFY_CSV_FORMAT
    CREDENTIALS = (AZURE_SAS_TOKEN = 'sp=rcwdl&st=2026-07-03T13:31:33Z&se=2026-07-31T21:46:33Z&sv=2026-02-06&sr=c&sig=CjRb8RhPskH3%2BOy7T9xOCD160vFkoKtIFRtpEqQfDLc%3D')
    COMMENT = 'Stage for albums data';

-- Stage for artist_data folder [2]
CREATE OR REPLACE STAGE STAGE_ARTISTS
    --STORAGE_INTEGRATION = AZURE_SPOTIFY_INTEGRATION
    URL = 'azure://spotifyetlstorageashu.blob.core.windows.net/spotify-transformed-data/artist_data/'
    FILE_FORMAT = SPOTIFY_CSV_FORMAT
    CREDENTIALS = (AZURE_SAS_TOKEN = 'sp=rcwdl&st=2026-07-03T13:31:33Z&se=2026-07-31T21:46:33Z&sv=2026-02-06&sr=c&sig=CjRb8RhPskH3%2BOy7T9xOCD160vFkoKtIFRtpEqQfDLc%3D')
    COMMENT = 'Stage for artists data';

-- Stage for songs folder [1]
CREATE OR REPLACE STAGE STAGE_SONGS
    --STORAGE_INTEGRATION = AZURE_SPOTIFY_INTEGRATION
    URL = 'azure://spotifyetlstorageashu.blob.core.windows.net/spotify-transformed-data/song_data/'
    FILE_FORMAT = SPOTIFY_CSV_FORMAT
    CREDENTIALS = (AZURE_SAS_TOKEN = 'sp=rcwdl&st=2026-07-03T13:31:33Z&se=2026-07-31T21:46:33Z&sv=2026-02-06&sr=c&sig=CjRb8RhPskH3%2BOy7T9xOCD160vFkoKtIFRtpEqQfDLc%3D')
    COMMENT = 'Stage for songs data';

LIST @STAGE_ALBUMS;
LIST @STAGE_ARTISTS;
LIST @STAGE_SONGS;

