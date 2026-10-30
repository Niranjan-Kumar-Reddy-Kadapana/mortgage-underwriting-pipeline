{{ config(materialized='incremental', incremental_strategy='append') }}

-- Immutable decision log. A decision is written once; it is never updated.
-- Each row stores the exact inputs and rule_version used, so the audit trail does not depend
-- on Time Travel alone (which expires). Corrections arrive as new applications, not edits.
select
    md5(m.application_id || '|' || '{{ var("rule_version") }}') as decision_id,
    m.application_id,
    m.applicant_key,
    m.application_date,
    m.property_state,
    m.loan_purpose,
    m.occupancy_type,
    m.loan_amount,
    m.property_value,
    m.monthly_gross_income,
    m.monthly_debt_obligations,
    m.fico_score,
    m.ltv_pct,
    m.dti_pct,
    m.decision_status,
    m.primary_reason_code,
    m.decline_reasons,
    '{{ var("rule_version") }}'  as rule_version,
    m.source_loaded_at           as silver_source_loaded_at,
    current_timestamp()          as decided_at
from {{ ref('int_underwriting_rules') }} m
{% if is_incremental() %}
where not exists (select 1 from {{ this }} t where t.application_id = m.application_id)
{% endif %}
