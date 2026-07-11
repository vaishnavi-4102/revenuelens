-- Account-level ARR waterfall: contract-grain movements from
-- fct_arr_movements netted up to one row per account per month. This is
-- the grain a finance analyst drills into from the CFO dashboard -- carries
-- legal_entity, so it's row-access scoped the same way dim_customer is
-- (reattached via post_hook every build, since +materialized: table means
-- every run is a fresh CREATE OR REPLACE TABLE).
{{
    config(
        post_hook=[
            "alter table {{ this }} add row access policy {{ target.database }}.MARTS_FINANCE.ENTITY_ACCESS_POLICY on (legal_entity)"
        ]
    )
}}

with movements as (

    select * from {{ ref('fct_arr_movements') }}

),

agg as (

    select
        month_end_date,
        account_id,
        region,
        legal_entity,
        sum(arr_usd) as account_arr_usd,
        sum(case when movement_type = 'new' then real_component_usd else 0 end) as new_arr_usd,
        sum(case when movement_type = 'expansion' then real_component_usd else 0 end) as expansion_arr_usd,
        sum(case when movement_type = 'contraction' then real_component_usd else 0 end) as contraction_arr_usd,
        sum(case when movement_type = 'churn' then real_component_usd else 0 end) as churn_arr_usd,
        sum(case when movement_type = 'reactivation' then real_component_usd else 0 end) as reactivation_arr_usd,
        sum(fx_component_usd) as fx_impact_usd
    from movements
    group by 1, 2, 3, 4

)

select * from agg
