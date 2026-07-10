import argparse
from datetime import date, timedelta

from generator.billing import generate_billing
from generator.config import load_config
from generator.crm import generate_contracts
from generator.customer_master import generate_customer_master
from generator.entities import generate_accounts
from generator.erp import generate_gl
from generator.fx import generate_fx_rates
from generator.late_events import inject_late_credit_memo
from generator.writer import write_backfill, write_daily


def build_datasets(cfg):
    accounts = generate_accounts(cfg)
    customer_master = generate_customer_master(accounts, cfg)
    contracts = generate_contracts(accounts, cfg)
    fx_rates = generate_fx_rates(cfg)
    invoices, invoice_line_items, credit_memos, payments = generate_billing(contracts, cfg)
    gl_journal_entries = generate_gl(invoices, payments, cfg)

    return {
        "accounts": accounts,
        "customer_master": customer_master,
        "contracts": contracts,
        "fx_rates": fx_rates,
        "invoices": invoices,
        "invoice_line_items": invoice_line_items,
        "credit_memos": credit_memos,
        "payments": payments,
        "gl_journal_entries": gl_journal_entries,
    }


def main():
    parser = argparse.ArgumentParser(description="RevenueLens synthetic data generator")
    parser.add_argument("mode", choices=["backfill", "daily"])
    parser.add_argument("--config", default="config.yaml")
    parser.add_argument("--as-of", default=None, help="YYYY-MM-DD, defaults to demo_anchor_date + 1 day")
    parser.add_argument(
        "--inject-late-credit-memo", action="store_true",
        help="Force one backdated credit memo to land on --as-of, for the D2 restatement demo",
    )
    args = parser.parse_args()

    cfg = load_config(args.config)
    datasets = build_datasets(cfg)

    if args.mode == "backfill":
        write_backfill(datasets, cfg.output_dir)
        print(f"Backfill written: {cfg.backfill_start} .. {cfg.backfill_end} -> {cfg.output_dir}/backfill/")
        for name, df in datasets.items():
            print(f"  {name}: {len(df):,} rows")
    else:
        as_of = date.fromisoformat(args.as_of) if args.as_of else cfg.demo_anchor_date + timedelta(days=1)
        if args.inject_late_credit_memo:
            datasets["credit_memos"] = inject_late_credit_memo(datasets, as_of, cfg)
        written = write_daily(datasets, as_of, cfg.output_dir)
        print(f"Daily incremental for {as_of} -> {cfg.output_dir}/daily/{as_of}/")
        if not written:
            print("  (no rows landed on this date)")
        for name, count in written.items():
            print(f"  {name}: {count:,} rows")


if __name__ == "__main__":
    main()
