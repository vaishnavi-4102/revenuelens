-- One row per calendar day covering the full observed data window. Bounds
-- are derived from the data itself (fx rates, contract effective dates,
-- account creation, invoice dates) rather than hardcoded, so the spine
-- always matches whatever window the generator was configured to produce.
--
-- Bounds are resolved via run_query() into compile-time literals rather
-- than passed to dbt_utils.date_spine() as a sibling-CTE subquery --
-- Snowflake doesn't resolve a CTE referenced from within date_spine's own
-- nested WITH block ("Object 'BOUNDS' does not exist"), so the subquery
-- has to be evaluated before date_spine ever sees it.
{% set bounds_query %}
    select
        min(d) as min_date,
        max(d) as max_date
    from (
        select rate_date as d from {{ ref('stg_fx__fx_rates') }}
        union all
        select effective_start_date as d from {{ ref('stg_crm__contracts') }}
        union all
        select account_created_date as d from {{ ref('stg_crm__accounts') }}
        union all
        select invoice_date as d from {{ ref('stg_billing__invoices') }}
    )
{% endset %}

{% if execute %}
    {% set bounds = run_query(bounds_query) %}
    {% set min_date = bounds.columns[0].values()[0] %}
    {% set max_date = bounds.columns[1].values()[0] %}
{% else %}
    {% set min_date = '2020-01-01' %}
    {% set max_date = '2020-01-01' %}
{% endif %}

with date_spine as (

    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('" ~ min_date ~ "' as date)",
        end_date="dateadd(day, 1, cast('" ~ max_date ~ "' as date))"
    ) }}

)

select cast(date_day as date) as date_day
from date_spine
