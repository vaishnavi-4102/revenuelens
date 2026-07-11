-- Current customer master state, one row per account. This is the D4
-- governance demo target: PII columns get a masking policy and
-- legal_entity gets the row access policy, both reattached via post_hook
-- on every build -- +materialized: table means each run is a fresh CREATE
-- OR REPLACE TABLE, and a policy never survives that, so post_hook (not a
-- one-time infra script) is the only place this can correctly live.
{{
    config(
        post_hook=[
            "alter table {{ this }} modify column billing_contact_name set masking policy {{ target.database }}.MARTS_FINANCE.MASK_PII_TEXT",
            "alter table {{ this }} modify column address_line1 set masking policy {{ target.database }}.MARTS_FINANCE.MASK_PII_TEXT",
            "alter table {{ this }} modify column billing_contact_email set masking policy {{ target.database }}.MARTS_FINANCE.MASK_EMAIL",
            "alter table {{ this }} modify column tax_id set masking policy {{ target.database }}.MARTS_FINANCE.MASK_TAX_ID",
            "alter table {{ this }} add row access policy {{ target.database }}.MARTS_FINANCE.ENTITY_ACCESS_POLICY on (legal_entity)"
        ]
    )
}}

select
    account_id,
    billing_contact_name,
    billing_contact_email,
    tax_id,
    address_line1,
    city,
    region,
    legal_entity,
    updated_at as customer_master_updated_at
from {{ ref('int_customer_master_versions') }}
where is_current_version
