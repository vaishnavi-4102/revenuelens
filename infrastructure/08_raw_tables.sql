-- RevenueLens :: RAW table DDL
-- Defines the RAW landing tables that COPY INTO / Snowpipe load the data
-- generator's CSV output into. Column lists match data_generator/generator/
-- exactly (source of truth: writer.py DATE_COLUMNS keys + each module's
-- output rows).
--
-- Every table carries a _loaded_at column defaulting to CURRENT_TIMESTAMP(),
-- populated automatically at INSERT/COPY time. This is a real, load-time
-- ingestion timestamp -- not a value dbt computes or infers -- and it is
-- what dbt source freshness checks key off (loaded_at_field: _loaded_at).
--
-- Defined once against RL_PROD, then mirrored to QA/DEV via CREATE TABLE
-- ... LIKE so the column list (including the _loaded_at default) isn't
-- repeated three times.
-- Idempotent: safe to re-run.

USE ROLE RL_LOADER;

-- ---------------------------------------------------------------------------
-- CRM
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS RL_PROD.RAW.ACCOUNTS (
    account_id      STRING,
    account_name    STRING,
    region          STRING,
    legal_entity    STRING,
    currency        STRING,
    segment         STRING,
    industry        STRING,
    created_date    DATE,
    _loaded_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'RAW CRM accounts, one row per account, landed from data_generator crm module';

CREATE TABLE IF NOT EXISTS RL_PROD.RAW.CONTRACTS (
    contract_id             STRING,
    version_number          NUMBER,
    account_id              STRING,
    effective_start_date    DATE,
    effective_end_date      DATE,
    arr_amount               NUMBER(18, 2),
    currency                STRING,
    seats                   NUMBER,
    plan_tier                STRING,
    amendment_type          STRING,
    created_at               DATE,
    is_backdated             BOOLEAN,
    co_termination_group    STRING,
    _loaded_at               TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'RAW CRM contract versions (original signature + amendments), one row per version';

-- ---------------------------------------------------------------------------
-- Customer master (PII)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS RL_PROD.RAW.CUSTOMER_MASTER (
    account_id              STRING,
    version                  NUMBER,
    billing_contact_name    STRING,
    billing_contact_email   STRING,
    tax_id                   STRING,
    address_line1            STRING,
    city                     STRING,
    region                   STRING,
    legal_entity             STRING,
    updated_at               DATE,
    _loaded_at                TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'RAW customer master versions (billing contact/address), one row per version. Contains PII.';

-- ---------------------------------------------------------------------------
-- Billing
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS RL_PROD.RAW.INVOICES (
    invoice_id      STRING,
    contract_id     STRING,
    account_id      STRING,
    invoice_date    DATE,
    currency        STRING,
    amount          NUMBER(18, 2),
    _loaded_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'RAW billing invoices, one row per invoice';

CREATE TABLE IF NOT EXISTS RL_PROD.RAW.INVOICE_LINE_ITEMS (
    invoice_line_id    STRING,
    invoice_id          STRING,
    description          STRING,
    quantity             NUMBER,
    unit_amount          NUMBER(18, 4),
    amount               NUMBER(18, 2),
    _loaded_at           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'RAW billing invoice line items, one row per line';

CREATE TABLE IF NOT EXISTS RL_PROD.RAW.CREDIT_MEMOS (
    credit_memo_id       STRING,
    invoice_id            STRING,
    account_id            STRING,
    issue_date             DATE,
    system_entry_date     DATE,
    currency               STRING,
    amount                 NUMBER(18, 2),
    reason                 STRING,
    _loaded_at             TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'RAW billing credit memos. issue_date vs system_entry_date gap is the late-arrival signal for D2.';

CREATE TABLE IF NOT EXISTS RL_PROD.RAW.PAYMENTS (
    payment_id      STRING,
    invoice_id       STRING,
    account_id       STRING,
    payment_date     DATE,
    amount           NUMBER(18, 2),
    currency         STRING,
    _loaded_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'RAW billing payments, one row per payment record (includes intentional duplicate-record messiness)';

-- ---------------------------------------------------------------------------
-- ERP
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS RL_PROD.RAW.GL_JOURNAL_ENTRIES (
    je_id            STRING,
    posting_date     DATE,
    gl_account       STRING,
    debit_credit     STRING,
    amount           NUMBER(18, 2),
    currency         STRING,
    reference_id     STRING,
    je_type          STRING,
    _loaded_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'RAW ERP GL journal entries, one row per JE line (auto-posted from invoices/payments plus manual adjustments)';

-- ---------------------------------------------------------------------------
-- FX
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS RL_PROD.RAW.FX_RATES (
    rate_date        DATE,
    base_currency    STRING,
    quote_currency   STRING,
    fx_rate          NUMBER(18, 6),
    _loaded_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'RAW daily FX rates, USD base. Weekends are intentionally absent (fill-forward is a dbt macro concern)';

-- ---------------------------------------------------------------------------
-- Mirror into QA and DEV (structure + defaults, no data)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS RL_QA.RAW.ACCOUNTS            LIKE RL_PROD.RAW.ACCOUNTS;
CREATE TABLE IF NOT EXISTS RL_QA.RAW.CONTRACTS            LIKE RL_PROD.RAW.CONTRACTS;
CREATE TABLE IF NOT EXISTS RL_QA.RAW.CUSTOMER_MASTER       LIKE RL_PROD.RAW.CUSTOMER_MASTER;
CREATE TABLE IF NOT EXISTS RL_QA.RAW.INVOICES              LIKE RL_PROD.RAW.INVOICES;
CREATE TABLE IF NOT EXISTS RL_QA.RAW.INVOICE_LINE_ITEMS    LIKE RL_PROD.RAW.INVOICE_LINE_ITEMS;
CREATE TABLE IF NOT EXISTS RL_QA.RAW.CREDIT_MEMOS          LIKE RL_PROD.RAW.CREDIT_MEMOS;
CREATE TABLE IF NOT EXISTS RL_QA.RAW.PAYMENTS              LIKE RL_PROD.RAW.PAYMENTS;
CREATE TABLE IF NOT EXISTS RL_QA.RAW.GL_JOURNAL_ENTRIES    LIKE RL_PROD.RAW.GL_JOURNAL_ENTRIES;
CREATE TABLE IF NOT EXISTS RL_QA.RAW.FX_RATES              LIKE RL_PROD.RAW.FX_RATES;

CREATE TABLE IF NOT EXISTS RL_DEV.RAW.ACCOUNTS            LIKE RL_PROD.RAW.ACCOUNTS;
CREATE TABLE IF NOT EXISTS RL_DEV.RAW.CONTRACTS            LIKE RL_PROD.RAW.CONTRACTS;
CREATE TABLE IF NOT EXISTS RL_DEV.RAW.CUSTOMER_MASTER       LIKE RL_PROD.RAW.CUSTOMER_MASTER;
CREATE TABLE IF NOT EXISTS RL_DEV.RAW.INVOICES              LIKE RL_PROD.RAW.INVOICES;
CREATE TABLE IF NOT EXISTS RL_DEV.RAW.INVOICE_LINE_ITEMS    LIKE RL_PROD.RAW.INVOICE_LINE_ITEMS;
CREATE TABLE IF NOT EXISTS RL_DEV.RAW.CREDIT_MEMOS          LIKE RL_PROD.RAW.CREDIT_MEMOS;
CREATE TABLE IF NOT EXISTS RL_DEV.RAW.PAYMENTS              LIKE RL_PROD.RAW.PAYMENTS;
CREATE TABLE IF NOT EXISTS RL_DEV.RAW.GL_JOURNAL_ENTRIES    LIKE RL_PROD.RAW.GL_JOURNAL_ENTRIES;
CREATE TABLE IF NOT EXISTS RL_DEV.RAW.FX_RATES              LIKE RL_PROD.RAW.FX_RATES;
