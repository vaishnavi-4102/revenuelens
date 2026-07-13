{#
  Anchors "how far back do we look for late-arriving data" to a specific
  point in time instead of always current_date()/current_timestamp().

  Without this, every dbt invocation -- including a manual backfill run for
  a historical Airflow logical date -- computes its lookback window
  relative to *today*, which defeats the point of backfilling a past date:
  a backfill for 2025-03-15 would still reprocess "the last 60 days from
  right now" instead of "the last 60 days from 2025-03-15".

  var('run_date') is set by 30_dbt_marts_and_tests.py from the Airflow
  logical date ({{ ds }}); it's absent for a normal interactive `dbt run`,
  which is when these macros fall back to the real current date/timestamp.
#}

{% macro as_of_timestamp() %}
    {%- set run_date = var('run_date', none) -%}
    {%- if run_date -%}
        '{{ run_date }}'::timestamp_ntz
    {%- else -%}
        current_timestamp()
    {%- endif -%}
{% endmacro %}

{% macro as_of_date() %}
    {%- set run_date = var('run_date', none) -%}
    {%- if run_date -%}
        '{{ run_date }}'::date
    {%- else -%}
        current_date()
    {%- endif -%}
{% endmacro %}
