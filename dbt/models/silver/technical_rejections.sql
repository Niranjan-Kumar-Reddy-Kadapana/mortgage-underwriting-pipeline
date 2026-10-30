{{ config(materialized='incremental', incremental_strategy='append') }}

-- Append-only log: one row per application per reason. Never updated, so it is a clean audit trail.
select
    j.application_id,
    j.applicant_id,
    f.value::string          as rejection_reason,
    j.application_date,
    j.loan_amount,
    j.property_state,
    j.source_loaded_at,
    current_timestamp()      as rejected_at,
    '{{ invocation_id }}'    as dbt_invocation_id
from {{ ref('int_applications_validated') }} j,
     lateral flatten(input => j.validation_errors) f
where j.processing_status = 'TECHNICAL_REJECTED'
{% if is_incremental() %}
  and not exists (
      select 1 from {{ this }} t
      where t.application_id = j.application_id
        and t.rejection_reason = f.value::string
  )
{% endif %}
