{{ config(materialized='table') }}

-- Merchant x month grain, rolled up from the daily intermediate. Because
-- int_merchant_daily has already collapsed to one row per merchant per day, summing
-- here is safe: there is no fan-out left to double count.

select
    merchant_id,
    merchant_name,
    merchant_segment,
    acquiring_region,
    mcc_description,
    date_trunc(month, auth_date)                          as auth_month,

    sum(auth_attempts)                                    as auth_attempts,
    sum(approved_count)                                   as approved_count,
    sum(declined_count)                                   as declined_count,
    sum(chargeback_count)                                 as chargeback_count,
    sum(processed_volume_eur)                             as processed_volume_eur,

    div0(sum(approved_count), sum(auth_attempts)) * 100   as approval_rate_pct,
    div0(sum(chargeback_count), sum(approved_count)) * 100 as chargeback_rate_pct,
    div0(sum(processed_volume_eur), sum(approved_count))  as avg_ticket_eur,
    count(distinct auth_date)                             as active_days

from {{ ref('int_merchant_daily') }}
group by 1, 2, 3, 4, 5, 6
