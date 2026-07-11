-- The CRM source already carries full SCD2-style history natively: every
-- amendment is recorded as a brand-new (contract_id, version_number) row,
-- never an in-place update (see stg_crm__contracts). effective_end_date is
-- only ever populated on the terminal churn row -- a version's real
-- validity window ends where the NEXT version's effective_start_date
-- begins (this matches how billing.py itself derives invoicing periods).
--
-- Because the source is already an immutable version log rather than a
-- mutable current-state table, dbt's `snapshot` mechanism has nothing to
-- add here -- it exists to reconstruct history dbt itself never saw, and
-- that history already exists in this table. This model is the
-- point-in-time reconstruction layer that a snapshot would otherwise feed.
with contracts as (

    select * from {{ ref('stg_crm__contracts') }}

),

accounts as (

    select account_id, region, legal_entity
    from {{ ref('stg_crm__accounts') }}

),

versioned as (

    select
        c.*,
        lead(effective_start_date) over (
            partition by contract_id order by version_number
        ) as next_version_start_date
    from contracts c

)

select
    v.contract_version_sk,
    v.contract_id,
    v.version_number,
    v.account_id,
    a.region,
    a.legal_entity,
    v.effective_start_date,
    -- Exclusive upper bound of this version's validity window.
    coalesce(v.next_version_start_date, v.effective_end_date, '9999-12-31') as effective_end_date_exclusive,
    v.arr_amount,
    v.currency,
    v.seats,
    v.plan_tier,
    v.amendment_type,
    v.contract_version_recorded_at,
    v.is_backdated,
    v.co_termination_group,
    (v.amendment_type = 'churn') as is_churn_version
from versioned v
left join accounts a on a.account_id = v.account_id
