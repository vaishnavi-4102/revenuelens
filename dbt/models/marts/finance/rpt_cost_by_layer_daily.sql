-- D5 cost story: spend by pipeline layer/model/warehouse/day. Reads
-- Snowflake's account-wide QUERY_HISTORY (ACCOUNT_USAGE is account-level
-- by nature, not scoped to RL_DEV/QA/PROD) filtered to this project's own
-- warehouses, parsing the QUERY_TAG JSON every model/invocation already
-- sets (macros/query_tag.sql).
--
-- Snowflake doesn't expose an exact credit cost per query -- it meters
-- per warehouse, not per query -- so estimated_credits apportions each
-- warehouse-day's actual metered credits (WAREHOUSE_METERING_HISTORY)
-- across that day's queries, weighted by elapsed time. This is a standard,
-- defensible approximation, not an exact figure; treat it as directional.
--
-- Needs RL_TRANSFORMER granted IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE
-- (03_rbac.sql) -- ACCOUNT_USAGE is invisible without it.
{{ config(materialized='view') }}

with queries as (

    select
        query_id,
        warehouse_name,
        date_trunc('day', start_time) as query_date,
        total_elapsed_time as elapsed_ms,
        try_parse_json(query_tag):app::string as app,
        try_parse_json(query_tag):project::string as project,
        try_parse_json(query_tag):target::string as dbt_target,
        try_parse_json(query_tag):schema::string as pipeline_layer,
        try_parse_json(query_tag):model::string as dbt_model
    from SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
    where warehouse_name in ('RL_LOADING_WH', 'RL_TRANSFORMING_WH', 'RL_BI_WH', 'RL_CI_WH')
      and query_tag is not null
      and query_tag != ''
      and start_time >= dateadd(day, -90, current_timestamp())

),

daily_warehouse_credits as (

    select
        warehouse_name,
        date_trunc('day', start_time) as usage_date,
        sum(credits_used) as credits_used
    from SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
    where warehouse_name in ('RL_LOADING_WH', 'RL_TRANSFORMING_WH', 'RL_BI_WH', 'RL_CI_WH')
      and start_time >= dateadd(day, -90, current_timestamp())
    group by 1, 2

),

daily_elapsed_totals as (

    select warehouse_name, query_date, sum(elapsed_ms) as total_elapsed_ms
    from queries
    group by 1, 2

)

select
    q.query_date,
    q.warehouse_name,
    coalesce(q.pipeline_layer, 'invocation_level') as pipeline_layer,
    q.dbt_model,
    q.dbt_target,
    count(*) as query_count,
    sum(q.elapsed_ms) as elapsed_ms,
    round(
        sum(q.elapsed_ms) / nullif(det.total_elapsed_ms, 0) * coalesce(dwc.credits_used, 0),
        4
    ) as estimated_credits
from queries q
left join daily_elapsed_totals det
    on det.warehouse_name = q.warehouse_name and det.query_date = q.query_date
left join daily_warehouse_credits dwc
    on dwc.warehouse_name = q.warehouse_name and dwc.usage_date = q.query_date
group by 1, 2, 3, 4, 5, det.total_elapsed_ms, dwc.credits_used
order by 1 desc, 2
