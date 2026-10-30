"""Generate synthetic mortgage applications (NDJSON) and credit bureau records (CSV).

Also writes expected_decisions.csv: the ground truth produced by an independent
Python implementation of the underwriting rules. Use it to reconcile dbt output.

All SSNs start with 9 (a range the SSA never issues), so no real SSN can appear.
"""
from __future__ import annotations

import argparse
import csv
import json
import random
from datetime import date, timedelta
from pathlib import Path

FIRST = ["Asha", "Ben", "Carla", "Dev", "Elena", "Femi", "Grace", "Hiro", "Ines", "Jamal",
         "Kira", "Liam", "Maya", "Noah", "Olu", "Priya", "Quinn", "Ravi", "Sofia", "Tariq"]
LAST = ["Anderson", "Brooks", "Chen", "Diaz", "Evans", "Fischer", "Garcia", "Hughes", "Ito",
        "Jones", "Khan", "Lopez", "Miller", "Nguyen", "Okafor", "Patel", "Reyes", "Smith"]
STATES = ["CA", "TX", "FL", "NY", "WA", "IL", "OH", "GA", "NC", "AZ"]
PURPOSES = ["PURCHASE", "REFINANCE", "HOME_IMPROVEMENT"]
OCCUPANCY = ["PRINCIPAL_RESIDENCE", "SECOND_RESIDENCE", "INVESTMENT"]

# Underwriting limits (must match dbt vars in dbt/dbt_project.yml)
MAX_LTV, MAX_DTI, MIN_FICO = 95, 43, 620
COSIGNER_MAX_FICO, COSIGNER_MIN_DTI = 660, 36


def decide(loan, value, income, debt, fico):
    """Reference implementation. Integer cross-multiplication, so no rounding risk."""
    reasons = []
    if fico < MIN_FICO:
        reasons.append("DECLINED_CREDIT_SCORE_BELOW_MIN")
    if debt * 100 > MAX_DTI * income:
        reasons.append("DECLINED_DTI_EXCEEDED")
    if loan * 100 > MAX_LTV * value:
        reasons.append("DECLINED_LTV_EXCEEDED")
    if reasons:
        return "DECLINED", reasons
    if MIN_FICO <= fico <= COSIGNER_MAX_FICO and debt * 100 >= COSIGNER_MIN_DTI * income:
        return "REQUIRES_COSIGNER", ["REQUIRES_COSIGNER"]
    return "APPROVED", ["APPROVED"]


def edge_cases():
    """Boundary values that the rules must handle exactly."""
    base = dict(loan=240_000, value=300_000, income=10_000, debt=2_000, fico=720)
    cases = [
        {},                                                # clean approval
        dict(loan=95_000, value=100_000),                  # LTV exactly 95  -> pass
        dict(loan=95_010, value=100_000),                  # LTV 95.01       -> decline
        dict(debt=4_300),                                  # DTI exactly 43  -> pass
        dict(debt=4_301),                                  # DTI 43.01       -> decline
        dict(fico=619),                                    # below 620       -> decline
        dict(fico=620),                                    # 620, DTI 20     -> approve
        dict(fico=620, debt=3_600),                        # 620, DTI 36     -> co-signer
        dict(fico=660, debt=4_300),                        # 660, DTI 43     -> co-signer
        dict(fico=661, debt=4_300),                        # 661, DTI 43     -> approve
        dict(fico=640, debt=3_599),                        # DTI 35.99       -> approve
        dict(fico=640, debt=3_600),                        # DTI 36          -> co-signer
        dict(fico=600, debt=5_000, loan=99_000, value=100_000),  # three reasons
    ]
    return [{**base, **c} for c in cases]


def random_case(rng):
    income = rng.randint(3_000, 20_000)
    value = rng.randint(150_000, 1_200_000)
    ltv = rng.uniform(50, 98)
    dti = rng.uniform(5, 48)
    fico = int(min(850, max(300, rng.gauss(700, 60))))
    return dict(loan=round(value * ltv / 100), value=value, income=income,
                debt=round(income * dti / 100), fico=fico)


def build(n, seed, late_pct):
    rng = random.Random(seed)
    specs = [(s, True) for s in edge_cases()]
    specs += [(random_case(rng), False) for _ in range(max(0, n - len(specs)))]
    apps, credit, late, expected = [], [], [], []
    for i, (s, is_edge) in enumerate(specs, start=1):
        app_id, aid = f"APP{i:07d}", f"APL{i:07d}"
        ssn = f"9{rng.randint(0, 99):02d}-{rng.randint(10, 99)}-{rng.randint(1000, 9999)}"
        app_date = date(2026, 1, 1) + timedelta(days=rng.randint(0, 300))
        app = dict(application_id=app_id, applicant_id=aid,
                   applicant_name=f"{rng.choice(FIRST)} {rng.choice(LAST)}",
                   application_date=app_date.isoformat(), loan_amount=s["loan"],
                   property_value=s["value"], monthly_gross_income=s["income"],
                   loan_purpose=rng.choice(PURPOSES), occupancy_type=rng.choice(OCCUPANCY),
                   property_state=rng.choice(STATES))
        cred = dict(applicant_id=aid, ssn=ssn, fico_score=s["fico"],
                    monthly_debt_obligations=s["debt"], report_date=app_date.isoformat())
        outcome, reason, has_credit, is_late = None, None, True, False

        r = rng.random() if not is_edge else 1.0
        if r < 0.015:
            cred["fico_score"] = ""; outcome, reason = "TECHNICAL_REJECTED", "MISSING_CREDIT_SCORE"
        elif r < 0.030:
            app["property_value"] = None; outcome, reason = "TECHNICAL_REJECTED", "MISSING_PROPERTY_VALUE"
        elif r < 0.035:
            app["monthly_gross_income"] = None; outcome, reason = "TECHNICAL_REJECTED", "MISSING_INCOME"
        elif r < 0.045:
            has_credit = False; outcome, reason = "TECHNICAL_REJECTED", "CREDIT_RECORD_NOT_RECEIVED"
        else:
            outcome, rs = decide(s["loan"], s["value"], s["income"], s["debt"], s["fico"])
            reason = rs[0]
            is_late = rng.random() < late_pct / 100
        apps.append(app)
        if rng.random() < 0.005:
            apps.append(dict(app))                      # retransmitted duplicate
        if has_credit:
            (late if is_late else credit).append(cred)
        expected.append(dict(application_id=app_id, expected_outcome=outcome,
                             expected_primary_reason=reason, credit_arrives_late=is_late))
    return apps, credit, late, expected


def write_csv(path, rows, fields):
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--out", default="data/out")
    p.add_argument("--rows", type=int, default=5000)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--batch", default="batch001", help="used in file names so loads are idempotent")
    p.add_argument("--late-pct", type=float, default=0.0,
                   help="percent of credit records written to <out>/late/ to simulate a delayed bureau")
    a = p.parse_args()

    out = Path(a.out); (out / "late").mkdir(parents=True, exist_ok=True)
    apps, credit, late, expected = build(a.rows, a.seed, a.late_pct)

    with open(out / f"applications_{a.batch}.json", "w") as f:
        for r in apps:
            f.write(json.dumps(r) + "\n")
    cfields = ["applicant_id", "ssn", "fico_score", "monthly_debt_obligations", "report_date"]
    write_csv(out / f"credit_bureau_{a.batch}.csv", credit, cfields)
    if late:
        write_csv(out / "late" / f"credit_bureau_late_{a.batch}.csv", late, cfields)
    write_csv(out / "expected_decisions.csv", expected,
              ["application_id", "expected_outcome", "expected_primary_reason", "credit_arrives_late"])
    print(f"apps={len(apps)} credit={len(credit)} late_credit={len(late)} -> {out}")


if __name__ == "__main__":
    main()
