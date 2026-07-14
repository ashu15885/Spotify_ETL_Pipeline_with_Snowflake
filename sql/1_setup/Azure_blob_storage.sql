-- Azure Blob Storage integration setup for Spotify data
-- Co-authored with CoCo
USE ROLE ACCOUNTADMIN;

-- Set these variables before running (replace the placeholder values):
SET azure_tenant_id = '<your-azure-tenant-id>';
SET azure_storage_location = 'azure://<your-account>.blob.core.windows.net/<your-container>/<path>/';

CREATE STORAGE INTEGRATION IF NOT EXISTS AZURE_SPOTIFY_INTEGRATION
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'AZURE'
  ENABLED = TRUE
  AZURE_TENANT_ID = $azure_tenant_id
  STORAGE_ALLOWED_LOCATIONS = ($azure_storage_location);
