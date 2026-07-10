from datetime import timedelta

import numpy as np
import pandas as pd

REGIONS = ["US", "EU", "IN"]
REGION_WEIGHTS = [0.55, 0.30, 0.15]
LEGAL_ENTITY = {
    "US": "Meridian Software Inc.",
    "EU": "Meridian Software Europe B.V.",
    "IN": "Meridian Software India Pvt. Ltd.",
}
CURRENCY = {"US": "USD", "EU": "EUR", "IN": "INR"}
SEGMENTS = ["SMB", "Mid-Market", "Enterprise"]
SEGMENT_WEIGHTS = [0.50, 0.35, 0.15]
INDUSTRIES = ["Software", "Fintech", "Healthcare", "Retail", "Manufacturing", "Media", "Logistics", "Education"]


def generate_accounts(cfg) -> pd.DataFrame:
    rng = np.random.default_rng(cfg.seed)
    n = cfg.n_accounts
    account_ids = [f"ACC-{i:06d}" for i in range(1, n + 1)]
    regions = rng.choice(REGIONS, size=n, p=REGION_WEIGHTS)
    segments = rng.choice(SEGMENTS, size=n, p=SEGMENT_WEIGHTS)
    industries = rng.choice(INDUSTRIES, size=n)

    # 70% of accounts are the existing customer base (created in the first
    # 10% of the window), 30% are new-logo growth spread across the rest --
    # a company at $80M ARR is mostly a renewal base, not all new logos, and
    # this materially affects invoice/GL volume (an account created mid-window
    # only bills for its remaining active months).
    window_days = (cfg.backfill_end - cfg.backfill_start).days
    n_existing = int(n * 0.7)
    n_new = n - n_existing
    existing_offsets = rng.integers(0, max(int(window_days * 0.1), 1), size=n_existing)
    new_offsets = rng.integers(int(window_days * 0.1), max(window_days - 30, 1), size=n_new)
    created_offsets = np.concatenate([existing_offsets, new_offsets])
    rng.shuffle(created_offsets)
    created_dates = [cfg.backfill_start + timedelta(days=int(o)) for o in created_offsets]

    return pd.DataFrame({
        "account_id": account_ids,
        "account_name": [f"{ind} {aid.split('-')[1]} Corp" for ind, aid in zip(industries, account_ids)],
        "region": regions,
        "legal_entity": [LEGAL_ENTITY[r] for r in regions],
        "currency": [CURRENCY[r] for r in regions],
        "segment": segments,
        "industry": industries,
        "created_date": created_dates,
    })
