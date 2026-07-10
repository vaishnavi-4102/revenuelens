import os

import pandas as pd

# Which column represents "when this row landed/changed", used to slice a
# single day's incremental output from the full deterministic dataset.
# None means the entity rides along with a parent (see invoice_line_items
# handling in write_daily).
DATE_COLUMNS = {
    "accounts": "created_date",
    "customer_master": "updated_at",
    "contracts": "created_at",
    "fx_rates": "rate_date",
    "invoices": "invoice_date",
    "invoice_line_items": None,
    "credit_memos": "system_entry_date",
    "payments": "payment_date",
    "gl_journal_entries": "posting_date",
}


def write_backfill(datasets: dict, output_dir: str) -> None:
    base = os.path.join(output_dir, "backfill")
    for name, df in datasets.items():
        folder = os.path.join(base, name)
        os.makedirs(folder, exist_ok=True)
        df.to_csv(os.path.join(folder, f"{name}.csv"), index=False)


def write_daily(datasets: dict, as_of_date, output_dir: str) -> dict:
    base = os.path.join(output_dir, "daily", str(as_of_date))
    written = {}

    for name, df in datasets.items():
        date_col = DATE_COLUMNS.get(name)
        if date_col is None:
            continue
        day_slice = df[pd.to_datetime(df[date_col]).dt.date == as_of_date]
        if day_slice.empty:
            continue
        folder = os.path.join(base, name)
        os.makedirs(folder, exist_ok=True)
        day_slice.to_csv(os.path.join(folder, f"{name}.csv"), index=False)
        written[name] = len(day_slice)

    if "invoices" in written:
        day_invoice_ids = datasets["invoices"].loc[
            pd.to_datetime(datasets["invoices"]["invoice_date"]).dt.date == as_of_date, "invoice_id"
        ]
        li_slice = datasets["invoice_line_items"][
            datasets["invoice_line_items"]["invoice_id"].isin(day_invoice_ids)
        ]
        if not li_slice.empty:
            folder = os.path.join(base, "invoice_line_items")
            os.makedirs(folder, exist_ok=True)
            li_slice.to_csv(os.path.join(folder, "invoice_line_items.csv"), index=False)
            written["invoice_line_items"] = len(li_slice)

    return written
