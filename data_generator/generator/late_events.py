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
        # Includes as_of_date, not just len(existing): the latter is
        # constant across every invocation (it's the full deterministic
        # dataset's total row count, independent of --as-of), so two
        # injections run on different days previously collided on the
        # identical literal ID "CM-DEMO-001798" -- confirmed live, this
        # silently discarded one session's injected row as a "duplicate"
        # of an unrelated one from a different day during RAW cleanup.
        "credit_memo_id": f"CM-DEMO-{as_of_date.isoformat()}-{len(existing) + 1:06d}",
        "invoice_id": inv["invoice_id"],
        "account_id": inv["account_id"],
        "issue_date": target_issue_date.date(),
        "system_entry_date": as_of_date,
        "currency": inv["currency"],
        "amount": round(float(inv["amount"]) * 0.5, 2),
        "reason": "billing_error",
    }
    return pd.concat([existing, pd.DataFrame([new_row])], ignore_index=True)
