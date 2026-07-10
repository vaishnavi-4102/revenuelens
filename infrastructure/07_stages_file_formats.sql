-- RevenueLens :: Stages & File Formats
--
-- Choice: INTERNAL named stages (not external S3/Azure/GCS).
-- Why: this is a demo/POC asset with a Python generator producing local
-- files -- adding a cloud storage account + IAM/SAS setup just to land CSVs
-- would add infra surface area with no payoff for the narrative (the story
-- is dbt/Airflow/Snowflake governance, not cloud storage integration).
-- Airflow's SnowflakeHook PUTs generator output straight into these internal
-- stages, then COPY INTO loads RAW tables. If this became a real production
-- build, the swap to an external stage is a one-file change (this file) --
-- nothing in dbt or the DAGs references the stage type directly.
--
-- One stage per source per environment, all living in the RAW schema since
-- that's the only layer that ever reads from a stage.
-- Idempotent: safe to re-run.

USE ROLE RL_LOADER;

-- ---------------------------------------------------------------------------
-- File formats
-- ---------------------------------------------------------------------------
CREATE FILE FORMAT IF NOT EXISTS RL_PROD.RAW.FF_CSV
    TYPE = CSV
    FIELD_DELIMITER = ','
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('', 'NULL', 'null')
    EMPTY_FIELD_AS_NULL = TRUE
    DATE_FORMAT = 'YYYY-MM-DD'
    TIMESTAMP_FORMAT = 'YYYY-MM-DD HH24:MI:SS'
    COMMENT = 'Standard CSV format for all generator output (CRM, billing, ERP, FX, customer master)';

CREATE FILE FORMAT IF NOT EXISTS RL_PROD.RAW.FF_JSON
    TYPE = JSON
    STRIP_OUTER_ARRAY = TRUE
    COMMENT = 'JSON format, reserved for any semi-structured payloads (e.g. contract amendment diffs)';

CREATE FILE FORMAT IF NOT EXISTS RL_QA.RAW.FF_CSV LIKE RL_PROD.RAW.FF_CSV;
CREATE FILE FORMAT IF NOT EXISTS RL_QA.RAW.FF_JSON LIKE RL_PROD.RAW.FF_JSON;
CREATE FILE FORMAT IF NOT EXISTS RL_DEV.RAW.FF_CSV LIKE RL_PROD.RAW.FF_CSV;
CREATE FILE FORMAT IF NOT EXISTS RL_DEV.RAW.FF_JSON LIKE RL_PROD.RAW.FF_JSON;

-- ---------------------------------------------------------------------------
-- Stages: one per source system, per environment.
-- DIRECTORY = enable so Airflow/COPY INTO can list staged files for
-- idempotency checks (skip already-loaded files by name/hash).
-- ---------------------------------------------------------------------------
CREATE STAGE IF NOT EXISTS RL_PROD.RAW.STG_CRM         DIRECTORY = (ENABLE = TRUE) FILE_FORMAT = RL_PROD.RAW.FF_CSV;
CREATE STAGE IF NOT EXISTS RL_PROD.RAW.STG_BILLING     DIRECTORY = (ENABLE = TRUE) FILE_FORMAT = RL_PROD.RAW.FF_CSV;
CREATE STAGE IF NOT EXISTS RL_PROD.RAW.STG_ERP         DIRECTORY = (ENABLE = TRUE) FILE_FORMAT = RL_PROD.RAW.FF_CSV;
CREATE STAGE IF NOT EXISTS RL_PROD.RAW.STG_FX          DIRECTORY = (ENABLE = TRUE) FILE_FORMAT = RL_PROD.RAW.FF_CSV;
CREATE STAGE IF NOT EXISTS RL_PROD.RAW.STG_CUSTOMER    DIRECTORY = (ENABLE = TRUE) FILE_FORMAT = RL_PROD.RAW.FF_CSV;

CREATE STAGE IF NOT EXISTS RL_QA.RAW.STG_CRM           DIRECTORY = (ENABLE = TRUE) FILE_FORMAT = RL_QA.RAW.FF_CSV;
CREATE STAGE IF NOT EXISTS RL_QA.RAW.STG_BILLING       DIRECTORY = (ENABLE = TRUE) FILE_FORMAT = RL_QA.RAW.FF_CSV;
CREATE STAGE IF NOT EXISTS RL_QA.RAW.STG_ERP           DIRECTORY = (ENABLE = TRUE) FILE_FORMAT = RL_QA.RAW.FF_CSV;
CREATE STAGE IF NOT EXISTS RL_QA.RAW.STG_FX            DIRECTORY = (ENABLE = TRUE) FILE_FORMAT = RL_QA.RAW.FF_CSV;
CREATE STAGE IF NOT EXISTS RL_QA.RAW.STG_CUSTOMER      DIRECTORY = (ENABLE = TRUE) FILE_FORMAT = RL_QA.RAW.FF_CSV;

CREATE STAGE IF NOT EXISTS RL_DEV.RAW.STG_CRM          DIRECTORY = (ENABLE = TRUE) FILE_FORMAT = RL_DEV.RAW.FF_CSV;
CREATE STAGE IF NOT EXISTS RL_DEV.RAW.STG_BILLING      DIRECTORY = (ENABLE = TRUE) FILE_FORMAT = RL_DEV.RAW.FF_CSV;
CREATE STAGE IF NOT EXISTS RL_DEV.RAW.STG_ERP          DIRECTORY = (ENABLE = TRUE) FILE_FORMAT = RL_DEV.RAW.FF_CSV;
CREATE STAGE IF NOT EXISTS RL_DEV.RAW.STG_FX           DIRECTORY = (ENABLE = TRUE) FILE_FORMAT = RL_DEV.RAW.FF_CSV;
CREATE STAGE IF NOT EXISTS RL_DEV.RAW.STG_CUSTOMER     DIRECTORY = (ENABLE = TRUE) FILE_FORMAT = RL_DEV.RAW.FF_CSV;

-- Note: RL_PROD.RAW.STG_BILLING is also the landing zone for the payments
-- CDC path -- Snowpipe or COPY INTO lands invoice/payment files here, and
-- 09_streams_tasks.sql (added once ingestion DAGs are built) layers a
-- Stream + Task on top of RAW.PAYMENTS (08_raw_tables.sql) to propagate
-- inserts into STAGING incrementally instead of waiting on the Airflow
-- transform DAG.
