# RevenueLens :: D1 CFO ARR Dashboard (Streamlit in Snowflake)
#
# Snowsight's classic "Legacy Dashboards" was deprecated mid-build (no new
# ones can be created in this account) -- Streamlit in Snowflake is the
# still-current, still-Snowsight-native replacement, so this app is what D1
# actually ships as. It supersedes the tile-by-tile plan in demo/dashboard/
# *.sql -- those files are kept as the underlying query logic reference,
# not as separate dashboard tiles anymore.
#
# Deliberately zero non-default packages (no plotly/altair): this Workspace
# flow installs packages via `uv` from PyPI at run time, which needs an
# External Access Integration to reach the internet at all -- without one,
# every install fails with a DNS/network error (confirmed live). streamlit +
# pandas + snowflake-snowpark-python ship with the app already, so sticking
# to those means nothing ever needs to be fetched.
#
# Deployed via `CREATE STREAMLIT` (demo/deploy_dashboard.py), not clicked
# through the Snowsight UI -- table references below are unqualified
# (MARTS_FINANCE.*, no database prefix) so the same file deploys correctly
# to RL_DEV/RL_QA/RL_PROD depending only on which database the app object
# itself is created in.
#
# To edit by hand instead: Snowsight -> Projects -> Streamlit -> open
# RL_CFO_ARR_DASHBOARD -> Edit, or re-run deploy_dashboard.py after changing
# this file.
import pandas as pd
import streamlit as st
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="RevenueLens CFO ARR Dashboard", layout="wide")
session = get_active_session()
# Do NOT call session.use_warehouse()/session.sql("USE WAREHOUSE ...") here
# -- confirmed live that Streamlit-in-Snowflake's sandboxed session rejects
# USE-family statements outright ("Object does not exist, or operation
# cannot be performed", not a privilege error -- the same statement runs
# fine as a plain SQL session with the same role). The warehouse has to
# come from QUERY_WAREHOUSE on the CREATE STREAMLIT object itself (see
# demo/deploy_dashboard.py).


def sql_to_df(query: str) -> pd.DataFrame:
    # .to_pandas(), not .collect(): the app's earlier "No active warehouse
    # selected" failures turned out to be a missing grant (RL_TRANSFORMER,
    # the app's OWNER -- Streamlit apps run with owner's rights, not the
    # viewer's -- had no USAGE on RL_BI_WH, the app's QUERY_WAREHOUSE; see
    # infrastructure/03_rbac.sql), not a .to_pandas()-specific issue as
    # first suspected. Reverted to .to_pandas() since manually building a
    # DataFrame from .collect() rows leaves NUMBER columns as raw Python
    # Decimal/object dtype, which st.bar_chart renders as empty with no
    # error -- confirmed live -- while .to_pandas() casts to proper numeric
    # dtypes automatically.
    return session.sql(query).to_pandas()


st.title("RevenueLens — CFO ARR Dashboard")
st.caption(
    "One number, one definition. Every figure here comes from "
    "fct_arr_waterfall_portfolio_monthly / fct_arr_waterfall_account_monthly "
    "-- see the dbt exposure `cfo_arr_dashboard` for full source lineage."
)

portfolio_monthly = sql_to_df(
    "select * from MARTS_FINANCE.FCT_ARR_WATERFALL_PORTFOLIO_MONTHLY order by month_end_date"
)

account_monthly = sql_to_df(
    """
    select MONTH_END_DATE, SEGMENT, REGION, ACCOUNT_ARR_USD
    from MARTS_FINANCE.FCT_ARR_WATERFALL_ACCOUNT_MONTHLY
    where MONTH_END_DATE = (select max(MONTH_END_DATE) from MARTS_FINANCE.FCT_ARR_WATERFALL_ACCOUNT_MONTHLY)
    """
)

latest = portfolio_monthly.iloc[-1]

# --- Tile 1: headline number ---------------------------------------------
mom_change = latest["TOTAL_ARR_USD"] - latest["PRIOR_TOTAL_ARR_USD"]
mom_pct = (mom_change / latest["PRIOR_TOTAL_ARR_USD"] * 100) if latest["PRIOR_TOTAL_ARR_USD"] else 0

col1, col2, col3 = st.columns(3)
col1.metric("Total ARR", f"${latest['TOTAL_ARR_USD']:,.0f}", f"{mom_pct:+.1f}% MoM")
col2.metric("New + Expansion", f"${latest['NEW_ARR_USD'] + latest['EXPANSION_ARR_USD']:,.0f}")
col3.metric("Contraction + Churn", f"${latest['CONTRACTION_ARR_USD'] + latest['CHURN_ARR_USD']:,.0f}")

# --- Tile 2: ARR waterfall bridge for the most recent month --------------
# No plotly available, so this is a plain labeled bar chart of each bridge
# component's signed value (not a floating/connected waterfall bar) --
# less visually polished, but every number is exact and it needs no extra
# package. The table underneath gives the precise running total per step.
st.subheader(f"ARR Waterfall — {latest['MONTH_END_DATE']}")

# Numbered labels ("1. Starting ARR"), not a pandas Categorical dtype --
# confirmed live that this account's bundled Streamlit (1.22.0-sa.10, quite
# old) throws a frontend TypeError ("Cannot read properties of undefined
# (reading 'metadata')") serializing a Categorical column to either
# st.dataframe OR st.table. Plain strings that happen to sort correctly
# sidesteps the crash entirely and, as a bonus, also fixes st.bar_chart's
# default alphabetical sort below with zero extra code.
COMPONENT_ORDER = [
    "1. Starting ARR", "2. New", "3. Expansion", "4. Reactivation",
    "5. Contraction", "6. Churn", "7. FX Impact", "8. Ending ARR",
]

bridge = pd.DataFrame({
    "component": COMPONENT_ORDER,
    "amount_usd": [
        latest["PRIOR_TOTAL_ARR_USD"],
        latest["NEW_ARR_USD"],
        latest["EXPANSION_ARR_USD"],
        latest["REACTIVATION_ARR_USD"],
        latest["CONTRACTION_ARR_USD"],
        latest["CHURN_ARR_USD"],
        latest["FX_IMPACT_USD"],
        latest["TOTAL_ARR_USD"],
    ],
})
bridge["running_total"] = [
    latest["PRIOR_TOTAL_ARR_USD"],
    latest["PRIOR_TOTAL_ARR_USD"] + latest["NEW_ARR_USD"],
    latest["PRIOR_TOTAL_ARR_USD"] + latest["NEW_ARR_USD"] + latest["EXPANSION_ARR_USD"],
    latest["PRIOR_TOTAL_ARR_USD"] + latest["NEW_ARR_USD"] + latest["EXPANSION_ARR_USD"] + latest["REACTIVATION_ARR_USD"],
    latest["PRIOR_TOTAL_ARR_USD"] + latest["NEW_ARR_USD"] + latest["EXPANSION_ARR_USD"] + latest["REACTIVATION_ARR_USD"] + latest["CONTRACTION_ARR_USD"],
    latest["PRIOR_TOTAL_ARR_USD"] + latest["NEW_ARR_USD"] + latest["EXPANSION_ARR_USD"] + latest["REACTIVATION_ARR_USD"] + latest["CONTRACTION_ARR_USD"] + latest["CHURN_ARR_USD"],
    latest["TOTAL_ARR_USD"],
    latest["TOTAL_ARR_USD"],
]

# st.table, not st.dataframe: st.dataframe is Streamlit's *interactive* grid
# widget and confirmed live to re-sort rows on render regardless of any
# ordering hint. st.table is a plain static table with no sort behavior at
# all -- the right widget for a fixed 8-row summary anyway.
st.table(bridge.set_index("component"))

# Starting/Ending ARR are charted separately from the movement components:
# putting an ~$80M anchor bar next to ~$1M monthly deltas on one linear
# axis makes the deltas invisible (confirmed live -- the movement bars
# didn't render at readable height at all against that scale).
movement_components = bridge[~bridge["component"].isin(["1. Starting ARR", "8. Ending ARR"])]
st.bar_chart(movement_components.set_index("component")["amount_usd"])

# --- Tile 3: 24-month trend, stacked by movement type ---------------------
# st.bar_chart stacks multiple numeric columns automatically when given a
# wide dataframe (one column per series) -- no melt/manual layering needed.
st.subheader("ARR Movement Trend")
trend_wide = portfolio_monthly.set_index("MONTH_END_DATE")[
    ["NEW_ARR_USD", "EXPANSION_ARR_USD", "REACTIVATION_ARR_USD", "CONTRACTION_ARR_USD", "CHURN_ARR_USD"]
].rename(columns=lambda c: c.replace("_ARR_USD", "").title())
st.bar_chart(trend_wide)

# --- Tiles 4 & 5: current ARR by segment and region -----------------------
col4, col5 = st.columns(2)

with col4:
    st.subheader("ARR by Segment")
    by_segment = account_monthly.groupby("SEGMENT", as_index=False)["ACCOUNT_ARR_USD"].sum()
    by_segment = by_segment.sort_values("ACCOUNT_ARR_USD", ascending=False)
    st.bar_chart(by_segment.set_index("SEGMENT")["ACCOUNT_ARR_USD"])

with col5:
    st.subheader("ARR by Region")
    by_region = account_monthly.groupby("REGION", as_index=False)["ACCOUNT_ARR_USD"].sum()
    by_region = by_region.sort_values("ACCOUNT_ARR_USD", ascending=False)
    st.bar_chart(by_region.set_index("REGION")["ACCOUNT_ARR_USD"])
