{{ config(tags=['gold']) }}
-- Gold must never carry direct identifiers. Any row returned = a PII column leaked into Gold.
select table_name, column_name
from {{ target.database }}.information_schema.columns
where table_schema = 'GOLD'
  and upper(column_name) in ('SSN', 'APPLICANT_NAME', 'APPLICANT_ID')
