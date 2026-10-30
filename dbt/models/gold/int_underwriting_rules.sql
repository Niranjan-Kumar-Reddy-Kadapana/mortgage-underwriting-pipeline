{{ config(materialized='view', schema='staging') }}

-- All underwriting logic lives here (and only here), so it can be unit tested.
-- Reads Silver but never selects ssn / applicant_name.
-- Pass/fail uses exact cross-multiplied comparisons; ltv_pct / dti_pct are for display only.
with src as (
    select
        application_id, applicant_key, application_date, property_state, loan_purpose, occupancy_type,
        loan_amount, property_value, monthly_gross_income, monthly_debt_obligations, fico_score,
        source_loaded_at
    from {{ ref('silver_loan_applications') }}
),
flags as (
    select
        *,
        {{ pct_ratio('loan_amount', 'property_value') }}                          as ltv_pct,
        {{ pct_ratio('monthly_debt_obligations', 'monthly_gross_income') }}       as dti_pct,
        fico_score < {{ var('min_credit_score') }}                                as fail_credit_score,
        {{ pct_exceeds('loan_amount', 'property_value', var('max_ltv_pct')) }}    as fail_ltv,
        {{ pct_exceeds('monthly_debt_obligations', 'monthly_gross_income', var('max_dti_pct')) }} as fail_dti,
        (
            fico_score between {{ var('min_credit_score') }} and {{ var('cosigner_max_credit_score') }}
            and {{ pct_at_least('monthly_debt_obligations', 'monthly_gross_income', var('cosigner_min_dti_pct')) }}
            and not {{ pct_exceeds('monthly_debt_obligations', 'monthly_gross_income', var('max_dti_pct')) }}
        )                                                                         as in_cosigner_band
    from src
),
reasons as (
    select
        *,
        array_construct_compact(
            iff(fail_credit_score, 'DECLINED_CREDIT_SCORE_BELOW_MIN', null),
            iff(fail_dti,          'DECLINED_DTI_EXCEEDED',           null),
            iff(fail_ltv,          'DECLINED_LTV_EXCEEDED',           null)
        ) as decline_reasons
    from flags
)
select
    *,
    case
        when array_size(decline_reasons) > 0 then 'DECLINED'
        when in_cosigner_band                then 'REQUIRES_COSIGNER'
        else 'APPROVED'
    end as decision_status,
    case
        when array_size(decline_reasons) > 0 then decline_reasons[0]::string
        when in_cosigner_band                then 'REQUIRES_COSIGNER'
        else 'APPROVED'
    end as primary_reason_code
from reasons
