-- D1 tile 5: current ARR by geography (US / EU / IN).
--
-- Snowsight setup: Chart type Bar. X-axis: region. Y-axis: arr_usd.
select
    region,
    sum(account_arr_usd) as arr_usd
from marts_finance.fct_arr_waterfall_account_monthly
where month_end_date = (select max(month_end_date) from marts_finance.fct_arr_waterfall_account_monthly)
group by region
order by arr_usd desc
