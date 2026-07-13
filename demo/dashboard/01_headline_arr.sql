-- D1 tile 1: Headline number -- current total ARR + month-over-month change.
-- "One number, one definition": every figure on this dashboard traces back
-- to fct_arr_waterfall_portfolio_monthly, which is declared as this
-- dashboard's dbt exposure (see dbt/models/marts/finance/_finance__exposures.yml)
-- -- `dbt docs generate` renders the lineage graph all the way from here
-- back to RAW.
--
-- Snowsight setup: run in a worksheet against MARTS_FINANCE, pin the result
-- to the dashboard, chart type "Table" or "Scorecard" (single row).
select
    month_end_date,
    total_arr_usd,
    total_arr_usd - prior_total_arr_usd as mom_change_usd,
    round(div0(total_arr_usd - prior_total_arr_usd, prior_total_arr_usd) * 100, 1) as mom_change_pct
from marts_finance.fct_arr_waterfall_portfolio_monthly
where month_end_date = (select max(month_end_date) from marts_finance.fct_arr_waterfall_portfolio_monthly)
