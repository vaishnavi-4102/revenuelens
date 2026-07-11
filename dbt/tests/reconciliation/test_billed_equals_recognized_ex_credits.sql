-- "Billed = Recognized + Deferred +/- Credits" (Definition of Done), now in
-- full: Deferred is always 0 (recognized-on-invoice-period simplification),
-- and credit memos ARE netted into recognized_net_of_credits_usd (folded in
-- once fct_revenue_reconciliation_monthly went incremental with a
-- late-arrival lookback -- see model header). So:
--   recognized_net_of_credits_usd = billed_usd + manual_adjustment_usd - credit_usd
select
    month_start,
    legal_entity,
    billed_usd,
    manual_adjustment_usd,
    credit_usd,
    recognized_net_of_credits_usd,
    round(recognized_net_of_credits_usd - billed_usd - manual_adjustment_usd + credit_usd, 2) as reconciliation_gap
from {{ ref('fct_revenue_reconciliation_monthly') }}
where abs(recognized_net_of_credits_usd - billed_usd - manual_adjustment_usd + credit_usd) > 1.00
