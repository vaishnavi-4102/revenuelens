{#
  Sets Snowflake's session-level QUERY_TAG (not a SQL comment -- the actual
  QUERY_TAG column that QUERY_HISTORY / the D5 cost-attribution view filters
  and groups on) so every query dbt issues can be attributed to a specific
  model, schema (layer) and invocation.

  set_query_tag() runs as a +pre-hook on every model: tag identifies this
  exact model build. reset_query_tag() runs as +post-hook and also wraps the
  whole invocation (on-run-start/on-run-end in dbt_project.yml), tagging
  anything outside an individual model (connection setup, seeds if added
  later) at the invocation level instead of leaving the previous model's tag
  dangling on the session.
#}

{% macro revenuelens_query_tag(model_node=none) %}
    {%- set tag_dict = {
        "app": "dbt",
        "project": "revenuelens",
        "target": target.name,
        "invocation_id": invocation_id
    } -%}
    {%- if model_node -%}
        {%- do tag_dict.update({"schema": model_node.schema, "model": model_node.identifier}) -%}
    {%- endif -%}
    {{ return(tojson(tag_dict)) }}
{% endmacro %}

{% macro set_query_tag() -%}
    {%- set tag = revenuelens_query_tag(this) -%}
    {% do run_query("ALTER SESSION SET QUERY_TAG = '" ~ tag ~ "'") %}
{%- endmacro %}

{% macro reset_query_tag() -%}
    {%- set tag = revenuelens_query_tag() -%}
    {% do run_query("ALTER SESSION SET QUERY_TAG = '" ~ tag ~ "'") %}
{%- endmacro %}
