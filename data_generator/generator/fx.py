from datetime import timedelta

import numpy as np
import pandas as pd

BASE_RATES = {"EUR": 0.92, "INR": 83.0}


def generate_fx_rates(cfg) -> pd.DataFrame:
    rng = np.random.default_rng(cfg.seed + 1)
    rows = []
    rates = dict(BASE_RATES)
    d = cfg.backfill_start

    while d <= cfg.backfill_end:
        # Weekends intentionally skipped -- fill-forward is a dbt macro
        # concern (per spec §4.2), not something the generator should mask.
        if d.weekday() < 5:
            for ccy, _ in BASE_RATES.items():
                drift = rng.normal(0, 0.002)
                rates[ccy] = max(rates[ccy] * (1 + drift), 0.01)
                rows.append({
                    "rate_date": d,
                    "base_currency": "USD",
                    "quote_currency": ccy,
                    "fx_rate": round(rates[ccy], 6),
                })
            rows.append({
                "rate_date": d,
                "base_currency": "USD",
                "quote_currency": "USD",
                "fx_rate": 1.0,
            })
        d += timedelta(days=1)

    return pd.DataFrame(rows)
