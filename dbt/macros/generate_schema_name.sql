{#
  Environment (DEV/QA/PROD) is resolved by the *database*, via
  profiles.yml's per-target `database:` value -- dbt's default
  generate_database_name macro already does the right thing there, so it
  isn't overridden here.

  Layer (RAW/STAGING/INTERMEDIATE/MARTS_FINANCE) is resolved by *schema*.
  dbt's default generate_schema_name concatenates target.schema with the
  model's custom schema (e.g. "dbt_default_staging"), which would defeat the
  point of fixed layer schemas. Every model in this project sets an explicit
  +schema for its layer, so this override just uses that value verbatim and
  falls back to target.schema only for the (currently nonexistent) case of a
  model with no custom schema at all.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
