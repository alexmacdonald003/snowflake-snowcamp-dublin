{{ config(materialized='view') }}

select
    product_id,
    product_name,
    channel,
    product_family,
    launched_year
from {{ source('raw', 'PAYMENT_PRODUCTS') }}
