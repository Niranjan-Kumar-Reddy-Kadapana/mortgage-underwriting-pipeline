{# Policies are created by Terraform (GOVERNANCE schema). dbt attaches them after every build,
   because CREATE OR REPLACE (full refresh) drops column policies. FORCE swaps an existing one. #}
{% macro apply_masking_policy(relation, column, policy) -%}
    alter table {{ relation }} modify column {{ column }}
    set masking policy {{ target.database }}.governance.{{ policy }} force
{%- endmacro %}
