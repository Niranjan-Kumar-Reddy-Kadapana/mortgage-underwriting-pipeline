"""Streamlit dashboard on the Gold aggregates. Connects as the ANALYST role (never sees PII)."""
import os

import pandas as pd
import snowflake.connector
import streamlit as st

st.set_page_config(page_title="Mortgage Underwriting", layout="wide")


@st.cache_data(ttl=300)
def q(sql: str) -> pd.DataFrame:
    conn = snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"], user=os.environ["SNOWFLAKE_USER"],
        password=os.environ["SNOWFLAKE_PASSWORD"], role="MORTGAGE_ANALYST_ROLE",
        warehouse="MORTGAGE_BI_WH", database=os.getenv("SNOWFLAKE_DATABASE", "MORTGAGE_DEV"), schema="GOLD")
    try:
        df = pd.read_sql(sql, conn)
    finally:
        conn.close()
    df.columns = [c.lower() for c in df.columns]
    return df


summary = q("select * from agg_decision_summary")
reasons = q("select * from agg_denial_reasons")

st.title("Mortgage underwriting overview")
approved = summary[summary.decision_status == "APPROVED"]
avg_fico = approved.fico_score_sum.sum() / max(approved.application_count.sum(), 1)
declined = summary[summary.decision_status == "DECLINED"]

c1, c2, c3 = st.columns(3)
c1.metric("Avg FICO, approved loans", f"{avg_fico:,.0f}")
c2.metric("Approved volume", f"${approved.total_loan_amount.sum():,.0f}")
c3.metric("Declined volume", f"${declined.total_loan_amount.sum():,.0f}")

left, right = st.columns(2)
with left:
    st.subheader("Loan volume by decision")
    st.bar_chart(summary.groupby("decision_status").total_loan_amount.sum())
with right:
    st.subheader("Denials by reason code (primary reason)")
    st.bar_chart(reasons.groupby("reason_code").primary_reason_count.sum())

st.subheader("Monthly decisions")
st.dataframe(summary.sort_values(["application_month", "decision_status"]), use_container_width=True)
