{# Display value: (num / den) * 100 rounded. Never use this for a pass/fail decision. #}
{% macro pct_ratio(num, den, scale=2) -%}
    round(({{ num }} * 100.0) / nullif({{ den }}, 0), {{ scale }})
{%- endmacro %}

{# Exact comparisons. num/den*100 > limit  <=>  num*100 > limit*den (den > 0).
   Cross-multiplying avoids decimal truncation, so 95.004 is never rounded down to 95. #}
{% macro pct_exceeds(num, den, threshold) -%}
    ({{ num }} * 100 > {{ threshold }} * {{ den }})
{%- endmacro %}

{% macro pct_at_least(num, den, threshold) -%}
    ({{ num }} * 100 >= {{ threshold }} * {{ den }})
{%- endmacro %}
