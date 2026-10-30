-- "What did applicant X's financial profile look like when they were approved 30 days ago?"
-- Needs DATA_RETENTION_TIME_IN_DAYS >= 30 on the schema (Terraform sets 90; Enterprise edition).

-- 1) When was the decision made, and with what inputs? (immutable copy, never expires)
select application_id, decision_status, primary_reason_code, decided_at, rule_version,
       loan_amount, property_value, monthly_gross_income, monthly_debt_obligations, fico_score, ltv_pct, dti_pct
from mortgage_prod.gold.fct_underwriting_decisions
where application_id = 'APP0000123';

-- 2) The Silver record exactly as it was at that moment (run as COMPLIANCE role to see SSN).
select *
from mortgage_prod.silver.silver_loan_applications
     at (timestamp => (select decided_at from mortgage_prod.gold.fct_underwriting_decisions
                       where application_id = 'APP0000123'))
where application_id = 'APP0000123';

-- 3) Offset form, or pin to the exact statement that made the decision:
-- ... at (offset => -60*60*24*30)
-- ... before (statement => '<query_id from query_history>')

-- 4) Freeze evidence for a dispute or audit: zero-copy clone at that moment.
create table mortgage_prod.audit.silver_snapshot_case_123 clone mortgage_prod.silver.silver_loan_applications
     at (timestamp => '2026-09-29 10:00:00'::timestamp_ltz);

-- 5) Oops recovery: undrop table / restore a table to a point in time via clone.
-- Time Travel ends at the retention limit, then 7 days of Fail-safe (Snowflake support only).
-- For regulatory retention (HMDA ~3 years) keep fct_underwriting_decisions: it stores the inputs.
