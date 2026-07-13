-- D1 tile 4: current ARR by customer segment (SMB / Mid-Market / Enterprise).
-- Segment comes from stg_crm__accounts, threaded through int_contract_arr_monthly
-- -> int_contract_arr_bridge_monthly -> fct_arr_movements -> this mart, so it
-- carries the same lineage guarantee as region/legal_entity.
--
-- Snowsight setup: Chart type Bar. X-axis: segment. Y-axis: arr_usd.
select
    segment,
    sum(account_arr_usd) as arr_usd
from marts_finance.fct_arr_waterfall_account_monthly
where month_end_date = (select max(month_end_date) from marts_finance.fct_arr_waterfall_account_monthly)
group by segment
order by arr_usd desc
