-- The ARR waterfall at its finest usable grain: one row per contract per
-- month it was active, classified into exactly one movement type. Kept at
-- contract grain (not netted to account level) on purpose -- an account
-- with two concurrent lifecycles (co_termination_group) can have a
-- downgrade on one contract and an upsell on the other in the same month,
-- and netting them at this layer would hide that both things happened.
-- fct_arr_waterfall_account_monthly nets them; this table is the drill-down
-- underneath it.
with bridge as (

    select * from {{ ref('int_contract_arr_bridge_monthly') }}

),

classified as (

    select
        *,
        case
            when contract_month_seq = 1 and prior_account_arr_usd = 0 and not account_ever_had_arr_before
                then 'new'
            when contract_month_seq = 1 and prior_account_arr_usd = 0 and account_ever_had_arr_before
                then 'reactivation'
            -- Contract's first month, but the account already had other
            -- ARR (a second concurrent lifecycle starting) -- a real
            -- account-level ARR increase, but not a new logo.
            when contract_month_seq = 1
                then 'expansion'
            when arr_usd = 0 and prior_arr_usd_filled > 0
                then 'churn'
            when real_component_usd > 0
                then 'expansion'
            when real_component_usd < 0
                then 'contraction'
            else 'no_change'
        end as movement_type
    from bridge

)

select
    {{ dbt_utils.generate_surrogate_key(['contract_id', 'month_end_date']) }} as arr_movement_sk,
    month_end_date,
    contract_id,
    account_id,
    region,
    legal_entity,
    currency,
    arr_local,
    arr_usd,
    prior_arr_usd_filled as prior_arr_usd,
    real_component_usd,
    fx_component_usd,
    movement_type
from classified
