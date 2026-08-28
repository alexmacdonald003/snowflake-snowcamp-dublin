{{ config(materialized='view') }}

select
    fee_line_id,
    auth_id,
    merchant_id,
    fee_type,
    fee_category,
    fee_amount_eur,
    fee_basis_points,
    calculated_on_amount,

    -- Pass-through fees are collected from the merchant and paid straight out to the
    -- issuer or the scheme. Only the acquirer's own components are revenue. Getting
    -- this wrong overstates income by roughly 40%.
    case
        when fee_category = 'Pass-through' then 0
        else fee_amount_eur
    end as acquirer_revenue_amount
from {{ source('raw', 'FEE_LINES') }}
