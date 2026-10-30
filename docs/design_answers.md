# Design answers

## 4a. The credit bureau API is late: applications land hours before credit scores

**Principle: late data is normal, so don't treat it as an error.**

- **Separate landing.** Each source lands independently in Bronze. Neither blocks the other.
- **A third state, not a rejection.** `int_applications_validated` marks an application with no bureau record as `PENDING_CREDIT` while it is inside an SLA window (`credit_sla_hours`, default 24). It is held back from Silver, so no decision is made on partial data.
- **Self-healing.** Silver is incremental on `source_loaded_at = greatest(app, credit load time)`. When the bureau file lands, the next run picks up the pending applications and moves them through Silver and Gold. No manual replay.
- **SLA breach is a business event.** After the window, the application becomes a `technical_rejections` row (`CREDIT_RECORD_NOT_RECEIVED`) and an alert fires, because the lender now has an unhappy applicant.
- **Orchestration.** Airflow runs `dbt source freshness` before Silver. For hard cut-offs, put a sensor with a timeout in front of Silver. For lower latency, trigger the dbt run from a Stream on `raw_credit_bureau` instead of a schedule.
- **Known edge case.** If bureau data arrives after the SLA, the application already has a rejection row. A warn-level test (`assert_no_application_both_decided_and_rejected...`) flags it for review. In production add a `superseded_at` column to the rejection log.
- **Observability.** Track pending count and age as a metric. A growing pending queue is the earliest sign the bureau feed is broken.

## 4b. Time Travel: what did the applicant's profile look like at approval, 30 days ago?

1. Read `decided_at` from `fct_underwriting_decisions`.
2. Query Silver `AT (TIMESTAMP => decided_at)` (see `snowflake/03_time_travel_audit.sql`). A compliance role sees clear SSN, and everyone else sees masked values, even in the past.
3. For a dispute, freeze it: `CREATE TABLE ... CLONE ... AT (...)` is zero-copy and keeps evidence after retention runs out.

What makes this work:

- **Retention must be long enough.** Terraform sets `DATA_RETENTION_TIME_IN_DAYS = 90` (Enterprise edition). The default is 1 day.
- **dbt's transient default.** dbt-snowflake creates transient tables by default, which cap Time Travel at 1 day. `+transient: false` fixes this.
- **Incremental, not rebuilt.** `CREATE OR REPLACE` starts a new table with no history. Silver is incremental merge and the decision log is append-only, so history is continuous.
- **Don't rely on Time Travel alone.** It expires, and mortgage records must be kept for years. The decision row stores the inputs, ratios, `rule_version` and timestamp, so the audit answer survives forever. Time Travel is the cross-check.

## 4c. End-of-quarter spike: 1,000x applications over a weekend

If normal is 5,000/day, the spike is about 5 million rows. That is small for Snowflake. The real risks are elsewhere:

| Risk | Mitigation |
|---|---|
| Ingestion backlog | Snowpipe is serverless and scales on its own. Land files of about 100-250 MB in cloud storage via a queue. Avoid millions of tiny files. |
| Processing time | Silver and Gold are incremental, so each run only touches new rows. Never run `--full-refresh` in the spike. Scale the transform warehouse up for the run (XSMALL to L) and back down. |
| Concurrent load (dbt + BI + auditors) | Separate warehouses per workload. Enable multi-cluster (`transform_max_clusters`) so queries scale out instead of queueing. |
| Bureau API rate limits | Usually the true bottleneck. Add retry with backoff and a queue, and let `PENDING_CREDIT` absorb the delay. |
| Orchestrator | Run micro-batches every 15 min during the surge (cheaper and fresher than one huge run). Set `max_active_runs=1` so runs never overlap. |
| Cost | Resource monitors with suspend thresholds, `AUTO_SUSPEND = 60`, and scale back down after the event. |
| Large-table scan time | If tables reach billions of rows, cluster Gold on `application_date`. Check pruning in the query profile first. |
| Confidence | Prove it before quarter-end: `generate_data.py --rows 5000000`, run the pipeline, record timings. |
