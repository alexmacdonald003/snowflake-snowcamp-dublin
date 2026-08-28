-- Fiserv Snowcamp Workshop: PAYMENT_PRODUCTS (10 rows).
-- Replaces the upstream retail PRODUCTS table. PRODUCT_ID values match the
-- payment_product_id assignment in 03_authorisations.sql.

USE ROLE ACCOUNTADMIN;
USE DATABASE FISERV_PAYMENTS_DB;
USE SCHEMA RAW;
USE WAREHOUSE FISERV_BUILD_WH;

CREATE OR REPLACE TABLE PAYMENT_PRODUCTS (
    PRODUCT_ID          NUMBER      COMMENT 'Payment product identifier',
    PRODUCT_NAME        VARCHAR     COMMENT 'Clover product or acceptance channel name',
    CHANNEL             VARCHAR     COMMENT 'Card present, E-commerce or MOTO',
    PRODUCT_FAMILY      VARCHAR     COMMENT 'Commercial grouping of the product',
    LAUNCHED_YEAR       NUMBER      COMMENT 'Year the product became generally available'
) COMMENT = 'Payment acceptance products merchants transact on';

INSERT INTO PAYMENT_PRODUCTS (PRODUCT_ID, PRODUCT_NAME, CHANNEL, PRODUCT_FAMILY, LAUNCHED_YEAR)
VALUES
    (1,  'Clover Station Duo',   'Card present', 'Countertop',   2019),
    (2,  'Clover Flex',          'Card present', 'Portable',     2018),
    (3,  'Clover Mini',          'Card present', 'Countertop',   2016),
    (4,  'Tap to Phone',         'Card present', 'Softpos',      2023),
    (5,  'Clover Online Store',  'E-commerce',   'Online',       2020),
    (6,  'Hosted Checkout',      'E-commerce',   'Online',       2017),
    (7,  'Pay by Link',          'E-commerce',   'Online',       2021),
    (8,  'Virtual Terminal',     'MOTO',         'Online',       2015),
    (9,  'Unattended / Fuel',    'Card present', 'Unattended',   2014),
    (10, 'Recurring Billing',    'E-commerce',   'Online',       2019);

-- Verification: product mix by authorisation volume.
SELECT
    p.PRODUCT_NAME,
    p.CHANNEL,
    COUNT(*)                                             AS authorisations,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)   AS pct_of_auths
FROM FISERV_PAYMENTS_DB.RAW.AUTHORISATIONS a
JOIN FISERV_PAYMENTS_DB.RAW.PAYMENT_PRODUCTS p
  ON p.PRODUCT_ID = a.PAYMENT_PRODUCT_ID
GROUP BY 1, 2
ORDER BY authorisations DESC;
