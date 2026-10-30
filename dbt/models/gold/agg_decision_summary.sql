{{ config(materialized='table') }}

-- Feeds the BI dashboard. fico_score_sum is kept so averages can be re-aggregated correctly.
select
    date_trunc('month', application_date)  as application_month,
    decision_status,
    count(*)                               as application_count,
    sum(loan_amount)                       as total_loan_amount,
    sum(fico_score)                        as fico_score_sum,
    round(avg(fico_score), 1)              as avg_fico_score,
    round(avg(ltv_pct), 2)                 as avg_ltv_pct,
    round(avg(dti_pct), 2)                 as avg_dti_pct
from {{ ref('fct_underwriting_decisions') }}
group by 1, 2
