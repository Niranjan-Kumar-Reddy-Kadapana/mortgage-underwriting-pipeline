# Plan, approach and suggestions

## Build order (about 5 working days)

| Day | Goal | Done when |
|---|---|---|
| 1 | Terraform + RBAC + masking policies. Data simulator with edge cases. | `terraform apply` clean, roles can/cannot see what they should |
| 2 | Bronze load, staging, validation, `technical_rejections` | 5k rows loaded twice, no duplicates; rejects logged with reasons |
| 3 | Silver masking, Gold rules, decision log, unit tests | All boundary unit tests pass; analyst sees masked SSN, compliance sees clear |
| 4 | Aggregates, HMDA view, secure share, Airflow DAG with alerts, dashboard | DAG green end to end; forced failure sends an alert |
| 5 | Docs, CI, reconciliation against `expected_decisions.csv`, load test | README quick start works from a clean clone |

Order matters: security and tests come before features, because they are what the evaluation scores most and the hardest to retrofit.

## Approach, in one line per evaluation criterion

- **Correct LTV/DTI/routing:** one place for the rules (`int_underwriting_rules`), exact comparisons, inclusive-boundary decisions written down, unit test per boundary, independent singular test, Python reference as ground truth.
- **dbt structure and materializations:** views for staging, incremental merge for Silver (keeps history), incremental append for the decision log (immutable), tables for small aggregates, secure view for HMDA, tags for the Airflow stages.
- **PII security:** masking policy objects in Terraform, attached by dbt post-hook, hidden STAGING schema, salted hash key so Gold carries no identifier, a test that fails if SSN or name appears in Gold.
- **Documentation:** Mermaid diagram that renders on GitHub, decisions called out explicitly rather than buried.

## Suggestions to stand out

1. **Reconcile against ground truth.** The generator writes `expected_decisions.csv`. A 20-line script that joins it to `fct_underwriting_decisions` and reports mismatches is a strong proof of correctness.
2. **Show the late-data flow live.** `make sim` (5% late) then `make load-late` demonstrates pending applications resolving themselves.
3. **Show masking live.** Run `select ssn from silver_loan_applications` as analyst, then as compliance.
4. **Tag-based masking** is the scalable upgrade: tag columns `PII`, bind one policy to the tag. Mention it even if you keep column policies.
5. **Row access policy** so analysts only see their region or state, if the interviewer pushes on least privilege.
6. **Dynamic Tables** are a Snowflake-native alternative to incremental dbt for Gold. Mention the trade-off (less control over immutability and audit).
7. **Cost guardrails:** resource monitors, `AUTO_SUSPEND = 60`, query tags per DAG run.
8. **Data contracts:** dbt `contract: enforced` on Gold models so a column change cannot silently break the HMDA report.
9. **Secrets:** key-pair auth for service users, salt in a secret manager, never in `profiles.yml`.

## Pitfalls to avoid

- Comparing rounded ratios at the 95 / 43 boundary.
- Rebuilding Silver with `CREATE OR REPLACE`: it drops masking policies and breaks Time Travel history.
- Letting analysts read any view that selects from Bronze.
- Hashing SSN without a secret salt (only 10^9 values, trivially reversible).
- Using protected-class fields (race, sex, age) in underwriting rules.
- Logging SSNs in Airflow logs, dbt logs or error messages.
- Treating late bureau data as an error instead of a state.
- Forgetting division by zero when income is 0.

## If you have extra time

Add `dbt snapshots` or an SCD2 table on `silver_loan_applications` for long-term history, a `superseded_at` flag for late-after-SLA cases, and a Great Expectations or dbt-expectations layer on Bronze.
