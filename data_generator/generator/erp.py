import numpy as np
import pandas as pd

REVENUE_ACCOUNT = "4000-SUBSCRIPTION-REVENUE"
AR_ACCOUNT = "1200-ACCOUNTS-RECEIVABLE"
CASH_ACCOUNT = "1000-CASH"
ADJ_ACCOUNT = "4900-REVENUE-ADJUSTMENT"


def generate_gl(invoices_df: pd.DataFrame, payments_df: pd.DataFrame, cfg) -> pd.DataFrame:
    rng = np.random.default_rng(cfg.seed + 4)
    rows = []
    je_seq = 1

    # Revenue recognized on invoice period (simplified per spec §8 -- full
    # ASC 606 schedules are a noted productionization extension, not built).
    for _, inv in invoices_df.iterrows():
        rows.append(_je(je_seq, inv["invoice_date"], REVENUE_ACCOUNT, "CREDIT", inv["amount"], inv["currency"], inv["invoice_id"], "AUTO_INVOICE")); je_seq += 1
        rows.append(_je(je_seq, inv["invoice_date"], AR_ACCOUNT, "DEBIT", inv["amount"], inv["currency"], inv["invoice_id"], "AUTO_INVOICE")); je_seq += 1

    for _, pay in payments_df.iterrows():
        rows.append(_je(je_seq, pay["payment_date"], CASH_ACCOUNT, "DEBIT", pay["amount"], pay["currency"], pay["invoice_id"], "AUTO_PAYMENT")); je_seq += 1
        rows.append(_je(je_seq, pay["payment_date"], AR_ACCOUNT, "CREDIT", pay["amount"], pay["currency"], pay["invoice_id"], "AUTO_PAYMENT")); je_seq += 1

    # Sparse manual adjustments (~1% of invoices), clearly tagged so the
    # reconciliation mart can isolate them -- they're small enough that the
    # billed/recognized/collected invariant still holds within FX-rounding
    # tolerance, matching the acceptance criterion.
    n_manual = max(int(len(invoices_df) * 0.01), 1)
    sample = invoices_df.sample(n=min(n_manual, len(invoices_df)), random_state=cfg.seed + 5)
    for _, inv in sample.iterrows():
        adj = round(float(rng.uniform(-5, 5)), 2)
        if adj == 0:
            continue
        adj_abs = abs(adj)
        adj_dc, rev_dc = ("DEBIT", "CREDIT") if adj > 0 else ("CREDIT", "DEBIT")
        rows.append(_je(je_seq, inv["invoice_date"], ADJ_ACCOUNT, adj_dc, adj_abs, inv["currency"], inv["invoice_id"], "MANUAL_ADJUSTMENT")); je_seq += 1
        rows.append(_je(je_seq, inv["invoice_date"], REVENUE_ACCOUNT, rev_dc, adj_abs, inv["currency"], inv["invoice_id"], "MANUAL_ADJUSTMENT")); je_seq += 1

    return pd.DataFrame(rows)


def _je(seq, posting_date, account, debit_credit, amount, currency, reference_id, je_type):
    return {
        "je_id": f"JE-{seq:07d}",
        "posting_date": posting_date,
        "gl_account": account,
        "debit_credit": debit_credit,
        "amount": amount,
        "currency": currency,
        "reference_id": reference_id,
        "je_type": je_type,
    }
