{{ config(materialized='table') }}

-- Fee economics at merchant x month x fee type grain.
--
-- This model is the reason total_fees and net_fee_revenue must stay separate
-- measures. total_fees is what the merchant was billed; net_fee_revenue is what
-- Fiserv keeps after interchange and scheme fees are passed out. Reporting the
-- former as revenue overstates income by roughly 40%.

with fees as (
    select
        f.merchant_id,
        date_trunc(month, a.auth_date) as auth_month,
        f.fee_type,
        f.fee_category,
        f.fee_amount_eur,
        f.acquirer_revenue_amount,
        f.calculated_on_amount
    from {{ ref('stg_fee_lines') }} f
    inner join {{ ref('stg_authorisations') }} a
        on f.auth_id = a.auth_id
)

select
    merchant_id,
    auth_month,
    -- FEE_TYPE carries planted NULLs. Coalescing them to a visible label rather than
    -- dropping the rows keeps the money reconciling while making the gap obvious in
    -- any group-by: an 'Unclassified' bucket with real euros in it is a data quality
    -- finding, whereas silently discarded rows are just a number that fails to add up.
    coalesce(fee_type, 'Unclassified') as fee_type,
    fee_category,

    count(*)                      as fee_line_count,
    sum(fee_amount_eur)           as total_fees_eur,
    sum(acquirer_revenue_amount)  as net_fee_revenue_eur,
    sum(calculated_on_amount)     as fee_basis_volume_eur,
    div0(sum(fee_amount_eur), sum(calculated_on_amount)) * 10000
                                  as effective_rate_bps

from fees
group by 1, 2, 3, 4
