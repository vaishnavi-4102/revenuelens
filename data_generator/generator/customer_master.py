from datetime import timedelta

import pandas as pd
from faker import Faker


def generate_customer_master(accounts_df: pd.DataFrame, cfg) -> pd.DataFrame:
    fake = Faker()
    Faker.seed(cfg.seed)
    window_days = (cfg.backfill_end - cfg.backfill_start).days
    rows = []

    for _, acc in accounts_df.iterrows():
        base_updated = acc["created_date"]
        tax_id = fake.bothify(text="??-#########").upper()

        rows.append({
            "account_id": acc["account_id"],
            "version": 1,
            "billing_contact_name": fake.name(),
            "billing_contact_email": fake.company_email(),
            "tax_id": tax_id,
            "address_line1": fake.street_address(),
            "city": fake.city(),
            "region": acc["region"],
            "legal_entity": acc["legal_entity"],
            "updated_at": base_updated,
        })

        # ~12% of accounts get a later contact/address change -> SCD2 fodder
        # for the customer_master snapshot (D3 "account changes" history).
        if fake.random.random() < 0.12:
            update_offset = fake.random_int(min=30, max=max(window_days - 1, 31))
            update_date = cfg.backfill_start + timedelta(days=update_offset)
            if update_date > base_updated:
                rows.append({
                    "account_id": acc["account_id"],
                    "version": 2,
                    "billing_contact_name": fake.name(),
                    "billing_contact_email": fake.company_email(),
                    "tax_id": tax_id,
                    "address_line1": fake.street_address(),
                    "city": fake.city(),
                    "region": acc["region"],
                    "legal_entity": acc["legal_entity"],
                    "updated_at": update_date,
                })

    return pd.DataFrame(rows).sort_values(["account_id", "version"]).reset_index(drop=True)
