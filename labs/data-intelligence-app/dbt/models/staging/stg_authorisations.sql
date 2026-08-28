{{ config(materialized='view') }}

select
    auth_id,
    merchant_id,
    payment_product_id,
    auth_timestamp,
    auth_timestamp::date              as auth_date,
    month(auth_timestamp)             as auth_month,
    auth_amount,
    currency_code,
    entry_mode,
    auth_result,
    decline_reason,
    card_bin,
    card_scheme,
    chargeback_flag,
    chargeback_reason,

    -- Approval flag as an integer so downstream models can sum it. Keeping the
    -- arithmetic here means no model has to re-encode the business rule that
    -- "Referred" is not an approval.
    case when auth_result = 'Approved' then 1 else 0 end as is_approved,

    -- Value that actually moved. Declined and referred attempts carry an amount but
    -- never settle, so summing AUTH_AMOUNT alone overstates processed volume.
    case when auth_result = 'Approved' then auth_amount else 0 end as approved_amount
from {{ source('raw', 'AUTHORISATIONS') }}
