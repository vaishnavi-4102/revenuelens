import numpy as np
import pandas as pd


def inject_late_credit_memo(datasets: dict, as_of_date, cfg, days_back: int = 45) -> pd.DataFrame:
    """Force one backdated credit memo to land on as_of_date, for the D2 demo trigger."""
    rng = np.random.default_rng(cfg.seed + 99)
    invoices = datasets["invoices"]
    target_issue_date = pd.Timestamp(as_of_date) - pd.Timedelta(days=days_back)
    candidates = invoices[pd.to_datetime(invoices["invoice_date"]).dt.date <= target_issue_date.date()]

    existing = datasets["credit_memos"]
    if candidates.empty:
        return existing

    inv = candidates.sample(n=1, random_state=int(rng.integers(0, 1_000_000))).iloc[0]
    new_row = {
        "credit_memo_id": f"CM-DEMO-{len(existing) + 1:06d}",
        "invoice_id": inv["invoice_id"],
        "account_id": inv["account_id"],
        "issue_date": target_issue_date.date(),
        "system_entry_date": as_of_date,
        "currency": inv["currency"],
        "amount": round(float(inv["amount"]) * 0.5, 2),
        "reason": "billing_error",
    }
    return pd.concat([existing, pd.DataFrame([new_row])], ignore_index=True)
