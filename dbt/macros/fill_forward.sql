{#
  Carries the last non-null value of `column_name` forward across a
  partition ordered by `order_by` -- used to fill weekend/holiday gaps in
  the FX feed (fx.py intentionally skips non-business days; per spec the
  fill-forward logic belongs in a dbt macro, not the generator).
#}
{% macro fill_forward(column_name, partition_by, order_by) %}
    last_value({{ column_name }} ignore nulls) over (
        partition by {{ partition_by }}
        order by {{ order_by }}
        rows between unbounded preceding and current row
    )
{% endmacro %}
