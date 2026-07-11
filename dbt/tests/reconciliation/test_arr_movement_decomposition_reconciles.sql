-- real_component_usd + fx_component_usd must sum exactly (modulo FX
-- rounding) to the period-over-period USD ARR delta, for every contract
-- every month. This is the algebraic identity the whole bridge design
-- depends on -- if it ever fails, the decomposition logic itself is wrong,
-- not just an edge case.
select
    contract_id,
    month_end_date,
    arr_usd,
    prior_arr_usd_filled,
    real_component_usd,
    fx_component_usd,
    round(arr_usd - prior_arr_usd_filled - real_component_usd - fx_component_usd, 2) as reconciliation_gap
from {{ ref('int_contract_arr_bridge_monthly') }}
where abs(arr_usd - prior_arr_usd_filled - real_component_usd - fx_component_usd) > 0.01
