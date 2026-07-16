{#
  dim_customer is `materialized: table`, which dbt-snowflake builds via a
  create-then-swap (not a literal DROP + CREATE), so the physical table
  object -- and any row access policy already attached to it -- survives
  the "replace". A plain `alter table ... add row access policy` in
  post_hook therefore only succeeds on the very first build; every build
  after that hits Snowflake error 003549 (an object may only have one row
  access policy attached at a time) because the policy from the prior run
  is still there. Checking POLICY_REFERENCES first makes the attach
  idempotent regardless of whether the swap preserved the old policy.
#}
{% macro reattach_row_access_policy(policy_name, columns) %}
  {% if execute %}
    {% set existing_query %}
      select policy_name
      from table(
        {{ target.database }}.information_schema.policy_references(
          ref_entity_name => '{{ this }}',
          ref_entity_domain => 'table'
        )
      )
      where policy_kind = 'ROW_ACCESS_POLICY'
    {% endset %}
    {% set existing = run_query(existing_query) %}
    {% if existing.rows | length == 0 %}
      {% do run_query("alter table " ~ this ~ " add row access policy " ~ policy_name ~ " on (" ~ columns ~ ")") %}
    {% endif %}
  {% endif %}
  {{ return('select 1') }}
{% endmacro %}
