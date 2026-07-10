from datetime import timedelta

import numpy as np
import pandas as pd

PLAN_TIERS = ["Starter", "Growth", "Enterprise"]
FOLLOWUP_AMENDMENT_TYPES = ["upsell", "downgrade", "renewal", "currency_change"]
CURRENCIES = ["USD", "EUR", "INR"]


def generate_contracts(accounts_df: pd.DataFrame, cfg) -> pd.DataFrame:
    rng = np.random.default_rng(cfg.seed + 2)
    window_days = (cfg.backfill_end - cfg.backfill_start).days
    rows = []
    contract_seq = 1
    lifecycles_by_account: dict[str, list[str]] = {}

    for _, acc in accounts_df.iterrows():
        n_lifecycles = int(rng.choice([1, 2], p=[0.85, 0.15]))
        lifecycles_by_account[acc["account_id"]] = []

        for lifecycle_idx in range(n_lifecycles):
            contract_id = f"CTR-{contract_seq:06d}"
            contract_seq += 1
            lifecycles_by_account[acc["account_id"]].append(contract_id)

            if lifecycle_idx == 0:
                # The account's primary contract starts shortly after they
                # became a customer, not at an independent random point in
                # the window -- otherwise most of the historical base would
                # show no billing history for months after "joining".
                signing_delay = int(rng.integers(0, 30))
                effective_start = min(acc["created_date"] + timedelta(days=signing_delay), cfg.backfill_end - timedelta(days=1))
            else:
                # Additional lifecycles (a second concurrent contract, e.g. a
                # new product line) can start anywhere later in the window.
                start_offset = int(rng.integers(0, max(window_days - 60, 1)))
                effective_start = max(acc["created_date"], cfg.backfill_start + timedelta(days=start_offset))
            seats = int(rng.integers(5, 500))
            currency = acc["currency"]
            arr = round(seats * rng.uniform(800, 2500), 2)
            version = 1

            rows.append(_row(
                contract_id, version, acc["account_id"], effective_start, None,
                arr, currency, seats, str(rng.choice(PLAN_TIERS)),
                "new", effective_start, False,
            ))

            cur_effective, cur_seats, cur_currency = effective_start, seats, currency
            n_amendments = int(rng.choice([0, 1, 2, 3], p=[0.35, 0.35, 0.20, 0.10]))

            for _ in range(n_amendments):
                gap = int(rng.integers(45, 180))
                amend_effective = cur_effective + timedelta(days=gap)
                if amend_effective >= cfg.backfill_end:
                    break

                version += 1
                a_type = str(rng.choice(FOLLOWUP_AMENDMENT_TYPES))
                if a_type == "upsell":
                    cur_seats = int(cur_seats * rng.uniform(1.1, 1.6))
                elif a_type == "downgrade":
                    cur_seats = max(1, int(cur_seats * rng.uniform(0.5, 0.9)))
                elif a_type == "currency_change":
                    cur_currency = str(rng.choice([c for c in CURRENCIES if c != cur_currency]))
                cur_arr = round(cur_seats * rng.uniform(800, 2500), 2)

                # Backdating messiness: ~25% of amendments are recorded in the
                # system weeks after they took effect.
                is_backdated = bool(rng.random() < 0.25)
                created_at = (
                    amend_effective + timedelta(days=int(rng.integers(10, 40)))
                    if is_backdated else amend_effective
                )

                rows.append(_row(
                    contract_id, version, acc["account_id"], amend_effective, None,
                    cur_arr, cur_currency, cur_seats, str(rng.choice(PLAN_TIERS)),
                    a_type, created_at, is_backdated,
                ))
                cur_effective = amend_effective

            # ~10% of lifecycles churn before the window ends.
            if rng.random() < 0.10 and cur_effective + timedelta(days=90) < cfg.backfill_end:
                churn_date = cur_effective + timedelta(days=int(rng.integers(60, 180)))
                if churn_date < cfg.backfill_end:
                    version += 1
                    rows.append(_row(
                        contract_id, version, acc["account_id"], churn_date, churn_date,
                        0.0, cur_currency, 0, str(rng.choice(PLAN_TIERS)),
                        "churn", churn_date, False,
                    ))
            # else: effective_end_date stays NULL on the latest version --
            # the "occasional missing end dates" messiness the spec asks for,
            # here it's simply the natural state of an ongoing contract.

    df = pd.DataFrame(rows)

    # Co-termination: accounts with two concurrent lifecycles share a group id
    # so downstream waterfall logic can be tested against aligned renewal dates.
    df["co_termination_group"] = df["account_id"].map(
        {acc: (acc if len(ids) > 1 else None) for acc, ids in lifecycles_by_account.items()}
    )

    return df.sort_values(["account_id", "contract_id", "version_number"]).reset_index(drop=True)


def _row(contract_id, version, account_id, eff_start, eff_end, arr, currency, seats, tier, amend_type, created_at, is_backdated):
    return {
        "contract_id": contract_id,
        "version_number": version,
        "account_id": account_id,
        "effective_start_date": eff_start,
        "effective_end_date": eff_end,
        "arr_amount": arr,
        "currency": currency,
        "seats": seats,
        "plan_tier": tier,
        "amendment_type": amend_type,
        "created_at": created_at,
        "is_backdated": is_backdated,
    }
