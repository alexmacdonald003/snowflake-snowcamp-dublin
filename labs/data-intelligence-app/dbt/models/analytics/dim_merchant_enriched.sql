{{ config(materialized='table') }}

-- Merchant dimension enriched with lifetime behaviour, one row per merchant.
-- Left join so merchants with no transactions in the window survive with zeroes
-- rather than vanishing: 154,241 of the 2M merchants have never transacted, and
-- losing them silently would misstate any "merchants by region" count.

with activity as (
    select
        merchant_id,
        sum(auth_attempts)        as lifetime_auth_attempts,
        sum(approved_count)       as lifetime_approved_count,
        sum(processed_volume_eur) as lifetime_volume_eur,
        sum(chargeback_count)     as lifetime_chargeback_count,
        min(auth_date)            as first_transaction_date,
        max(auth_date)            as last_transaction_date
    from {{ ref('int_merchant_daily') }}
    group by 1
)

select
    m.merchant_id,
    m.merchant_name,
    m.mcc,
    m.mcc_description,
    m.merchant_segment,
    m.risk_tier,
    m.country_code,
    m.acquiring_region,
    m.onboarded_date,
    m.tenure_months,
    m.terminal_count,

    coalesce(a.lifetime_auth_attempts, 0)    as lifetime_auth_attempts,
    coalesce(a.lifetime_approved_count, 0)   as lifetime_approved_count,
    coalesce(a.lifetime_volume_eur, 0)       as lifetime_volume_eur,
    coalesce(a.lifetime_chargeback_count, 0) as lifetime_chargeback_count,
    a.first_transaction_date,
    a.last_transaction_date,

    div0(a.lifetime_approved_count, a.lifetime_auth_attempts) * 100
                                             as lifetime_approval_rate_pct,
    case when a.merchant_id is null then false else true end as has_transacted

from {{ ref('stg_merchants') }} m
left join activity a
    on m.merchant_id = a.merchant_id
