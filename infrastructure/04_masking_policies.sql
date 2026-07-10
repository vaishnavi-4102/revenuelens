-- RevenueLens :: Dynamic Data Masking policies
-- Defines reusable masking policies for customer PII (billing contact email,
-- tax ID). Policy OBJECTS are created here, in every environment, because
-- dbt builds run against DEV/QA/PROD alike -- but ATTACHING a policy to a
-- column (ALTER TABLE ... MODIFY COLUMN ... SET MASKING POLICY) happens in
-- dbt via a post-hook on the mart/snapshot models that own these columns
-- (customer_master snapshot, dim_customer), once those models exist in P2.
-- That keeps the policy logic in version control next to the model it
-- protects, rather than duplicated here against tables that don't exist yet.
--
-- Unmasked: RL_ADMIN, RL_TRANSFORMER, RL_REVENUE_CONTROLLER
-- Masked:   everyone else (RL_FINANCE_ANALYST, RL_BI_READER, and any future role)
--
-- Idempotent: safe to re-run.

USE ROLE RL_ADMIN;

-- Email: show local-part first char + domain, e.g. "j***@acme.com".
CREATE OR REPLACE MASKING POLICY RL_PROD.MARTS_FINANCE.MASK_EMAIL AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('RL_ADMIN', 'RL_TRANSFORMER', 'RL_REVENUE_CONTROLLER') THEN val
        WHEN val IS NULL THEN NULL
        ELSE CONCAT(LEFT(val, 1), '***@', SPLIT_PART(val, '@', -1))
    END;

-- Tax ID: fully redact for non-privileged roles.
CREATE OR REPLACE MASKING POLICY RL_PROD.MARTS_FINANCE.MASK_TAX_ID AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('RL_ADMIN', 'RL_TRANSFORMER', 'RL_REVENUE_CONTROLLER') THEN val
        WHEN val IS NULL THEN NULL
        ELSE '***MASKED***'
    END;

-- Generic name/address masking used for billing contact name / address lines.
CREATE OR REPLACE MASKING POLICY RL_PROD.MARTS_FINANCE.MASK_PII_TEXT AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('RL_ADMIN', 'RL_TRANSFORMER', 'RL_REVENUE_CONTROLLER') THEN val
        WHEN val IS NULL THEN NULL
        ELSE '***MASKED***'
    END;

-- Same three policies, mirrored into QA and DEV so dbt post-hooks resolve
-- identically regardless of target environment.
CREATE OR REPLACE MASKING POLICY RL_QA.MARTS_FINANCE.MASK_EMAIL AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('RL_ADMIN', 'RL_TRANSFORMER', 'RL_REVENUE_CONTROLLER') THEN val
        WHEN val IS NULL THEN NULL
        ELSE CONCAT(LEFT(val, 1), '***@', SPLIT_PART(val, '@', -1))
    END;
CREATE OR REPLACE MASKING POLICY RL_QA.MARTS_FINANCE.MASK_TAX_ID AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('RL_ADMIN', 'RL_TRANSFORMER', 'RL_REVENUE_CONTROLLER') THEN val
        WHEN val IS NULL THEN NULL
        ELSE '***MASKED***'
    END;
CREATE OR REPLACE MASKING POLICY RL_QA.MARTS_FINANCE.MASK_PII_TEXT AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('RL_ADMIN', 'RL_TRANSFORMER', 'RL_REVENUE_CONTROLLER') THEN val
        WHEN val IS NULL THEN NULL
        ELSE '***MASKED***'
    END;

CREATE OR REPLACE MASKING POLICY RL_DEV.MARTS_FINANCE.MASK_EMAIL AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('RL_ADMIN', 'RL_TRANSFORMER', 'RL_REVENUE_CONTROLLER') THEN val
        WHEN val IS NULL THEN NULL
        ELSE CONCAT(LEFT(val, 1), '***@', SPLIT_PART(val, '@', -1))
    END;
CREATE OR REPLACE MASKING POLICY RL_DEV.MARTS_FINANCE.MASK_TAX_ID AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('RL_ADMIN', 'RL_TRANSFORMER', 'RL_REVENUE_CONTROLLER') THEN val
        WHEN val IS NULL THEN NULL
        ELSE '***MASKED***'
    END;
CREATE OR REPLACE MASKING POLICY RL_DEV.MARTS_FINANCE.MASK_PII_TEXT AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('RL_ADMIN', 'RL_TRANSFORMER', 'RL_REVENUE_CONTROLLER') THEN val
        WHEN val IS NULL THEN NULL
        ELSE '***MASKED***'
    END;

-- Example attachment (this is what the dbt post-hook will do at model-build
-- time -- shown here only for reference, not executed):
-- ALTER TABLE RL_PROD.MARTS_FINANCE.DIM_CUSTOMER
--     MODIFY COLUMN billing_contact_email SET MASKING POLICY RL_PROD.MARTS_FINANCE.MASK_EMAIL;
