-- A rate outside 0-100 means the approval numerator and denominator have come from
-- different grains, which is exactly what a fee-line fan-out would cause.
-- Returns rows on failure.
select merchant_id, auth_month, approval_rate_pct
from {{ ref('fct_merchant_performance') }}
where approval_rate_pct < 0 or approval_rate_pct > 100
