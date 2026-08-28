-- The whole point of the three-model chain is that rolling up does not change the
-- money. If processed volume in the monthly fact drifts from the raw approved total
-- by more than a cent, a join has fanned out somewhere.
with fact_total as (
    select sum(processed_volume_eur) as v from {{ ref('fct_merchant_performance') }}
),
raw_total as (
    select sum(approved_amount) as v from {{ ref('stg_authorisations') }}
)
select f.v as fact_volume, r.v as raw_volume, abs(f.v - r.v) as difference
from fact_total f cross join raw_total r
where abs(f.v - r.v) > 0.01
