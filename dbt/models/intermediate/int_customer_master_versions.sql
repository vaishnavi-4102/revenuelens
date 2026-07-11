-- Same pattern as int_contract_versions: stg_customer__customer_master is
-- already an append-only version log (~12% of accounts get a version-2 row
-- for a later contact/address change -- see customer_master.py), not a
-- mutable current-state table, so there's nothing here for dbt's snapshot
-- mechanism to reconstruct that isn't already in the data. This is the
-- point-in-time layer a snapshot would otherwise feed.
with customer_master as (

    select * from {{ ref('stg_customer__customer_master') }}

),

versioned as (

    select
        cm.*,
        lead(updated_at) over (
            partition by account_id order by customer_master_version
        ) as next_version_updated_at,
        row_number() over (
            partition by account_id order by customer_master_version desc
        ) = 1 as is_current_version
    from customer_master cm

)

select
    customer_master_sk,
    account_id,
    customer_master_version,
    billing_contact_name,
    billing_contact_email,
    tax_id,
    address_line1,
    city,
    region,
    legal_entity,
    updated_at,
    -- Exclusive upper bound of this version's validity window.
    coalesce(next_version_updated_at, '9999-12-31') as effective_end_date_exclusive,
    is_current_version
from versioned
