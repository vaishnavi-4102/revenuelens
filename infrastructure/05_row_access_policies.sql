-- RevenueLens :: Row Access Policy
-- Restricts RL_FINANCE_ANALYST to rows for their assigned legal entity/region.
-- Every other functional role sees all entities. Like the masking policies
-- (04), the policy OBJECT is created here; ATTACHING it to a mart's
-- legal_entity column happens via dbt post-hook once that column exists
-- (fct_arr_waterfall, fct_revenue_recon, dim_customer -- P2).
--
-- Entity assignment is data-driven via a mapping table rather than hardcoded
-- in the policy body, so onboarding a new analyst is an INSERT, not a DDL
-- change -- this is what makes D4 a "log in and look" demo instead of a
-- rebuild-the-policy demo.
--
-- Idempotent: safe to re-run.

USE ROLE RL_ADMIN;

CREATE TABLE IF NOT EXISTS RL_PROD.MARTS_FINANCE.ANALYST_ENTITY_ACCESS (
    user_name    STRING NOT NULL,
    legal_entity STRING NOT NULL,
    granted_at   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Maps RL_FINANCE_ANALYST users to the legal entity/region they may see. Row access policy source of truth.';

CREATE TABLE IF NOT EXISTS RL_QA.MARTS_FINANCE.ANALYST_ENTITY_ACCESS (
    user_name    STRING NOT NULL,
    legal_entity STRING NOT NULL,
    granted_at   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Maps RL_FINANCE_ANALYST users to the legal entity/region they may see. Row access policy source of truth.';

CREATE TABLE IF NOT EXISTS RL_DEV.MARTS_FINANCE.ANALYST_ENTITY_ACCESS (
    user_name    STRING NOT NULL,
    legal_entity STRING NOT NULL,
    granted_at   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Maps RL_FINANCE_ANALYST users to the legal entity/region they may see. Row access policy source of truth.';

CREATE OR REPLACE ROW ACCESS POLICY RL_PROD.MARTS_FINANCE.ENTITY_ACCESS_POLICY
    AS (legal_entity STRING) RETURNS BOOLEAN ->
    CURRENT_ROLE() IN ('RL_ADMIN', 'RL_TRANSFORMER', 'RL_REVENUE_CONTROLLER', 'RL_BI_READER')
    OR EXISTS (
        SELECT 1
        FROM RL_PROD.MARTS_FINANCE.ANALYST_ENTITY_ACCESS a
        WHERE a.user_name = CURRENT_USER()
          AND a.legal_entity = legal_entity
    );

CREATE OR REPLACE ROW ACCESS POLICY RL_QA.MARTS_FINANCE.ENTITY_ACCESS_POLICY
    AS (legal_entity STRING) RETURNS BOOLEAN ->
    CURRENT_ROLE() IN ('RL_ADMIN', 'RL_TRANSFORMER', 'RL_REVENUE_CONTROLLER', 'RL_BI_READER')
    OR EXISTS (
        SELECT 1
        FROM RL_QA.MARTS_FINANCE.ANALYST_ENTITY_ACCESS a
        WHERE a.user_name = CURRENT_USER()
          AND a.legal_entity = legal_entity
    );

CREATE OR REPLACE ROW ACCESS POLICY RL_DEV.MARTS_FINANCE.ENTITY_ACCESS_POLICY
    AS (legal_entity STRING) RETURNS BOOLEAN ->
    CURRENT_ROLE() IN ('RL_ADMIN', 'RL_TRANSFORMER', 'RL_REVENUE_CONTROLLER', 'RL_BI_READER')
    OR EXISTS (
        SELECT 1
        FROM RL_DEV.MARTS_FINANCE.ANALYST_ENTITY_ACCESS a
        WHERE a.user_name = CURRENT_USER()
          AND a.legal_entity = legal_entity
    );

-- Example seed for the D4 demo (edit user_name to match the real demo login):
-- INSERT INTO RL_PROD.MARTS_FINANCE.ANALYST_ENTITY_ACCESS (user_name, legal_entity)
-- VALUES ('DEMO_FINANCE_ANALYST', 'US');

-- Example attachment (performed by dbt post-hook once the mart exists):
-- ALTER TABLE RL_PROD.MARTS_FINANCE.FCT_ARR_WATERFALL
--     ADD ROW ACCESS POLICY RL_PROD.MARTS_FINANCE.ENTITY_ACCESS_POLICY ON (legal_entity);
