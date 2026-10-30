{{ config(materialized='view', secure=true) }}

-- HMDA-style loan/application register. Secure view so it can be shared with auditors.
-- No SSN, no name: applicant_key is a salted hash. Simplified mapping for the case study,
-- not a filing-ready LAR. action_taken: 2 = approved, 3 = denied, 5 = file closed incomplete.
-- REQUIRES_COSIGNER is a non-final status, so action_taken is NULL until the applicant resolves it.
with decided as (
    select
        d.application_id, d.applicant_key, d.application_date, d.property_state,
        d.loan_purpose, d.occupancy_type, d.loan_amount, d.property_value,
        d.ltv_pct as combined_ltv_pct, d.dti_pct, d.decision_status,
        case d.decision_status when 'APPROVED' then 2 when 'DECLINED' then 3 end as action_taken_code,
        r1.hmda_denial_reason_code as denial_reason_1,
        r2.hmda_denial_reason_code as denial_reason_2,
        r3.hmda_denial_reason_code as denial_reason_3,
        d.rule_version, d.decided_at
    from {{ ref('fct_underwriting_decisions') }} d
    left join {{ ref('dim_reason_codes') }} r1
        on d.decision_status = 'DECLINED' and r1.reason_code = d.decline_reasons[0]::string
    left join {{ ref('dim_reason_codes') }} r2
        on d.decision_status = 'DECLINED' and r2.reason_code = d.decline_reasons[1]::string
    left join {{ ref('dim_reason_codes') }} r3
        on d.decision_status = 'DECLINED' and r3.reason_code = d.decline_reasons[2]::string
),
incomplete as (
    select
        application_id,
        cast(null as varchar)        as applicant_key,
        any_value(application_date)  as application_date,
        any_value(property_state)    as property_state,
        cast(null as varchar)        as loan_purpose,
        cast(null as varchar)        as occupancy_type,
        any_value(loan_amount)       as loan_amount,
        cast(null as number)         as property_value,
        cast(null as number)         as combined_ltv_pct,
        cast(null as number)         as dti_pct,
        'TECHNICAL_REJECTED'         as decision_status,
        5                            as action_taken_code,
        cast(null as number)         as denial_reason_1,
        cast(null as number)         as denial_reason_2,
        cast(null as number)         as denial_reason_3,
        cast(null as varchar)        as rule_version,
        max(rejected_at)             as decided_at
    from {{ ref('technical_rejections') }}
    group by application_id
)
select * from decided
union all
select * from incomplete
