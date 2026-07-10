from datetime import timedelta

import numpy as np
import pandas as pd


def generate_billing(contracts_df: pd.DataFrame, cfg):
    rng = np.random.default_rng(cfg.seed + 3)
    invoices, line_items, credit_memos, payments = [], [], [], []
    inv_seq = cm_seq = pay_seq = 1

    for contract_id, group in contracts_df.groupby("contract_id"):
        group = group.sort_values("version_number").reset_index(drop=True)

        for idx, ver in group.iterrows():
            if ver["arr_amount"] <= 0:
                continue  # churn row: no billing

            period_start = ver["effective_start_date"]
            period_end = (
                group.loc[idx + 1, "effective_start_date"] if idx + 1 < len(group)
                else (ver["effective_end_date"] or cfg.backfill_end)
            )
            period_end = min(period_end, cfg.backfill_end)
            if period_end <= period_start:
                continue

            monthly_amount = round(ver["arr_amount"] / 12, 2)
            d = period_start
            while d < period_end:
                invoice_id = f"INV-{inv_seq:07d}"
                inv_seq += 1
                invoices.append({
                    "invoice_id": invoice_id,
                    "contract_id": contract_id,
                    "account_id": ver["account_id"],
                    "invoice_date": d,
                    "currency": ver["currency"],
                    "amount": monthly_amount,
                })
                line_items.append({
                    "invoice_line_id": f"{invoice_id}-L1",
                    "invoice_id": invoice_id,
                    "description": f"{ver['plan_tier']} plan - {ver['seats']} seats",
                    "quantity": ver["seats"],
                    "unit_amount": round(monthly_amount / max(ver["seats"], 1), 4),
                    "amount": monthly_amount,
                })

                pay_seq = _generate_payments(payments, pay_seq, rng, invoice_id, ver, d, monthly_amount)
                cm_seq = _maybe_generate_credit_memo(credit_memos, cm_seq, rng, invoice_id, ver, d, monthly_amount, cfg)

                d += timedelta(days=30)

    return (
        pd.DataFrame(invoices),
        pd.DataFrame(line_items),
        pd.DataFrame(credit_memos),
        pd.DataFrame(payments),
    )


def _generate_payments(payments, pay_seq, rng, invoice_id, ver, invoice_date, amount) -> int:
    pay_date = invoice_date + timedelta(days=int(rng.integers(1, 20)))
    roll = rng.random()

    if roll < 0.92:  # paid in full, on time
        payments.append(_payment(pay_seq, invoice_id, ver, pay_date, amount)); pay_seq += 1
    elif roll < 0.97:  # partial payment split across two records
        partial = round(amount * rng.uniform(0.3, 0.8), 2)
        payments.append(_payment(pay_seq, invoice_id, ver, pay_date, partial)); pay_seq += 1
        remainder_date = pay_date + timedelta(days=int(rng.integers(5, 15)))
        payments.append(_payment(pay_seq, invoice_id, ver, remainder_date, round(amount - partial, 2))); pay_seq += 1
    else:  # duplicate payment record messiness
        payments.append(_payment(pay_seq, invoice_id, ver, pay_date, amount)); pay_seq += 1
        if rng.random() < 0.5:
            payments.append(_payment(pay_seq, invoice_id, ver, pay_date, amount)); pay_seq += 1

    return pay_seq


def _maybe_generate_credit_memo(credit_memos, cm_seq, rng, invoice_id, ver, invoice_date, amount, cfg) -> int:
    if rng.random() >= 0.04:
        return cm_seq

    issue_date = invoice_date + timedelta(days=int(rng.integers(5, 30)))
    system_entry_date = issue_date + timedelta(days=int(rng.integers(5, 30)))
    if system_entry_date > cfg.backfill_end:
        return cm_seq

    credit_memos.append({
        "credit_memo_id": f"CM-{cm_seq:06d}",
        "invoice_id": invoice_id,
        "account_id": ver["account_id"],
        "issue_date": issue_date,
        "system_entry_date": system_entry_date,
        "currency": ver["currency"],
        "amount": round(amount * rng.uniform(0.1, 1.0), 2),
        "reason": str(rng.choice(["service_credit", "billing_error", "goodwill", "downgrade_proration"])),
    })
    return cm_seq + 1


def _payment(seq, invoice_id, ver, pay_date, amount):
    return {
        "payment_id": f"PAY-{seq:07d}",
        "invoice_id": invoice_id,
        "account_id": ver["account_id"],
        "payment_date": pay_date,
        "amount": amount,
        "currency": ver["currency"],
    }
