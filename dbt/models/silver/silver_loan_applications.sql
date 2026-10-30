{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='application_id',
    post_hook=[
        "{{ apply_masking_policy(this, 'ssn', 'mask_ssn') }}",
        "{{ apply_masking_policy(this, 'applicant_name', 'mask_applicant_name') }}"
    ]
) }}

-- Cleaned + joined master record. ssn and applicant_name are protected by masking policies.
-- Incremental + merge keeps one table over time, so Time Travel gives a real history
-- (a full-refresh CREATE OR REPLACE would orphan it).
select
    application_id,
    applicant_id,
    -- pseudonymous join key for Gold. Salted so a 9-digit SSN cannot be brute-forced from the hash.
    sha2(ssn || '{{ env_var("SSN_HASH_SALT", "dev-only-salt") }}', 256) as applicant_key,
    applicant_name,
    ssn,
    application_date,
    loan_amount,
    property_value,
    monthly_gross_income,
    monthly_debt_obligations,
    fico_score,
    loan_purpose,
    occupancy_type,
    property_state,
    source_loaded_at,
    current_timestamp() as silver_processed_at
from {{ ref('int_applications_validated') }}
where processing_status = 'VALIDATED'
{% if is_incremental() %}
  and source_loaded_at > (select coalesce(max(source_loaded_at), '1900-01-01'::timestamp_ltz) from {{ this }})
{% endif %}
