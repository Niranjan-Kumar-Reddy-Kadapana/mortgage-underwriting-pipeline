{{ config(tags=['gold']) }}
-- Re-derive DECLINED straight from the raw inputs with a separate expression.
-- Any row returned = the model and the policy disagree.
select application_id
from {{ ref('fct_underwriting_decisions') }}
where (decision_status = 'DECLINED') <>
      (   loan_amount * 100 > {{ var('max_ltv_pct') }} * property_value
       or monthly_debt_obligations * 100 > {{ var('max_dti_pct') }} * monthly_gross_income
       or fico_score < {{ var('min_credit_score') }})
