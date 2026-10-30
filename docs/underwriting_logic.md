# LTV and DTI logic

## Formulas

```
LTV = (loan_amount / property_value)        x 100
DTI = (monthly_debt_obligations / monthly_gross_income) x 100
```

## Rules (applied to VALIDATED Silver rows)

| Rule | Condition | Reason code |
|---|---|---|
| FICO floor | `fico_score < 620` | `DECLINED_CREDIT_SCORE_BELOW_MIN` |
| DTI limit | `DTI > 43` | `DECLINED_DTI_EXCEEDED` |
| LTV limit | `LTV > 95` | `DECLINED_LTV_EXCEEDED` |
| Co-signer | not declined, `620 <= FICO <= 660`, `36 <= DTI <= 43` | `REQUIRES_COSIGNER` |
| Otherwise | | `APPROVED` |

All thresholds are dbt vars in `dbt/dbt_project.yml`. Change a limit there and bump `rule_version`.

## Decisions I made where the brief is silent

1. **Boundaries are inclusive for passing.** LTV of exactly 95 and DTI of exactly 43 are approved. "Exceeds" means strictly greater. FICO 620 passes. The co-signer band is inclusive on all four edges.
2. **Exact comparison, rounded display.** The pass/fail test is `loan * 100 > 95 * property_value`, not `ltv > 95`. Division on decimals can truncate, so 95.004 could display as 95.00 and slip through. `ltv_pct` and `dti_pct` are rounded to 2 decimals for reporting only.
3. **All failing rules are recorded.** `decline_reasons` holds every breach in priority order (FICO, DTI, LTV). `primary_reason_code` is the first. HMDA allows several denial reasons, and the dashboard counts the primary one once per application.
4. **Zero or negative income / property value is a technical rejection**, never a divide-by-zero.
5. **Co-signer is not final.** It is a routing status. HMDA `action_taken` stays empty until the applicant resolves it.
6. **Protected-class attributes are not inputs to any rule.** Fair-lending (ECOA) risk.

## Worked boundary examples

| Loan | Value | Debt | Income | FICO | LTV | DTI | Result |
|---|---|---|---|---|---|---|---|
| 95,000 | 100,000 | 2,000 | 10,000 | 720 | 95.00 | 20.00 | APPROVED |
| 95,010 | 100,000 | 2,000 | 10,000 | 720 | 95.01 | 20.00 | DECLINED_LTV_EXCEEDED |
| 240,000 | 300,000 | 4,300 | 10,000 | 700 | 80.00 | 43.00 | APPROVED |
| 240,000 | 300,000 | 4,301 | 10,000 | 700 | 80.00 | 43.01 | DECLINED_DTI_EXCEEDED |
| 240,000 | 300,000 | 3,600 | 10,000 | 620 | 80.00 | 36.00 | REQUIRES_COSIGNER |
| 99,000 | 100,000 | 5,000 | 10,000 | 600 | 99.00 | 50.00 | DECLINED (3 reasons, primary = FICO) |

Each row is a dbt unit test (`dbt/models/gold/_unit_tests.yml`) and a Python test (`tests/test_rules.py`).
