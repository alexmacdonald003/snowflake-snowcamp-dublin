{{ config(materialized='table') }}

-- Merchant x day grain. Built from authorisations only, never joined to fee lines,
-- because fee lines fan out roughly three to one and would triple every count here.
-- Fee economics live in fct_fee_economics, at their own grain.

select
    a.merchant_id,
    m.merchant_name,
    m.merchant_segment,
    m.acquiring_region,
    m.mcc_description,
    a.auth_date,

    count(a.auth_id)                                    as auth_attempts,
    sum(a.is_approved)                                  as approved_count,
    sum(a.approved_amount)                              as processed_volume_eur,
    count_if(a.auth_result = 'Declined')                as declined_count,
    count_if(a.chargeback_flag)                         as chargeback_count,

    div0(sum(a.is_approved), count(a.auth_id)) * 100    as approval_rate_pct,
    div0(sum(a.approved_amount), sum(a.is_approved))    as avg_ticket_eur

from {{ ref('stg_authorisations') }} a
inner join {{ ref('stg_merchants') }} m
    on a.merchant_id = m.merchant_id
group by 1, 2, 3, 4, 5, 6
