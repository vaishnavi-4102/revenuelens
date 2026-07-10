from dataclasses import dataclass
from datetime import date, timedelta

import yaml


@dataclass
class Config:
    seed: int
    n_accounts: int
    backfill_months: int
    demo_anchor_date: date
    output_dir: str

    @property
    def backfill_start(self) -> date:
        return self.demo_anchor_date - timedelta(days=self.backfill_months * 30)

    @property
    def backfill_end(self) -> date:
        return self.demo_anchor_date


def load_config(path: str = "config.yaml") -> Config:
    with open(path) as f:
        raw = yaml.safe_load(f)
    return Config(
        seed=raw["seed"],
        n_accounts=raw["n_accounts"],
        backfill_months=raw["backfill_months"],
        demo_anchor_date=date.fromisoformat(raw["demo_anchor_date"]),
        output_dir=raw.get("output_dir", "output"),
    )
