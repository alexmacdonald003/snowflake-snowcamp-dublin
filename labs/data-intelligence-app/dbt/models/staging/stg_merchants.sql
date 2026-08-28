{{ config(materialized='view') }}

select
    merchant_id,
    dba_name             as merchant_name,
    mcc,
    mcc_description,
    merchant_segment,
    risk_tier,
    country_code,
    acquiring_region,
    onboarded_date,
    terminal_count,
    datediff(month, onboarded_date, current_date()) as tenure_months
from {{ source('raw', 'MERCHANTS') }}
