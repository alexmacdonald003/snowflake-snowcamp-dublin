-- Net fee revenue can never exceed total fees billed. If it does, the pass-through
-- exclusion has been inverted.
select fee_type, sum(total_fees_eur) as total_fees, sum(net_fee_revenue_eur) as net_revenue
from {{ ref('fct_fee_economics') }}
group by 1
having sum(net_fee_revenue_eur) > sum(total_fees_eur)
