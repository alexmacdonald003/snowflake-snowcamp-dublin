-- Fiserv Snowcamp 101: environment and seed data.
--
-- DELIBERATELY SMALL. The day-two dataset is 2M merchants and 10M authorisations because
-- those modules need volume to demonstrate concurrency and incremental refresh. The 101 needs
-- the opposite: data an attendee can read, count and reason about in their head while they
-- learn what a warehouse is. 5,000 merchants and 500,000 transactions loads in seconds and
-- still shows warehouse scaling on an aggregate.
--
-- Same payments domain as day two on purpose, so day two feels like the same business rather
-- than a new one. Separate database so nothing an attendee does here can break the day-two
-- lab, and so the 101 can be rebuilt independently during the workshop.

USE ROLE ACCOUNTADMIN;

CREATE DATABASE IF NOT EXISTS FISERV_101_DB;
USE DATABASE FISERV_101_DB;

CREATE SCHEMA IF NOT EXISTS RAW;        -- source tables and the JSON stage
CREATE SCHEMA IF NOT EXISTS ANALYTICS;  -- transformations and the dynamic table
CREATE SCHEMA IF NOT EXISTS GOVERNED;   -- session 3: RBAC, masking, AISQL

-- Two warehouses so session 1 can compare them. XSMALL is the working default; SMALL exists
-- purely so attendees can watch the same query get faster and then decide whether it was
-- worth twice the credits.
CREATE WAREHOUSE IF NOT EXISTS FISERV_101_WH
  WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Default 101 warehouse.';

CREATE WAREHOUSE IF NOT EXISTS FISERV_101_BIG_WH
  WAREHOUSE_SIZE = SMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Session 1 comparison warehouse. One size up, so the difference is visible but the cost is obvious.';

USE SCHEMA RAW;
USE WAREHOUSE FISERV_101_WH;

-- 5,000 merchants.
CREATE OR REPLACE TABLE MERCHANTS AS
WITH gen AS (
    SELECT SEQ4() + 1 AS merchant_id,
           UNIFORM(0, 999999, RANDOM(11)) AS r1,
           UNIFORM(0, 999999, RANDOM(12)) AS r2,
           UNIFORM(0, 999999, RANDOM(13)) AS r3
    FROM TABLE(GENERATOR(ROWCOUNT => 5000))
)
SELECT
    merchant_id AS MERCHANT_ID,
    -- Name suffix and category are derived from the SAME value on purpose. Deriving them
    -- independently produces "Castle Cafe" categorised as Florist and "Station Pharmacy" as
    -- Grocery. Merchant names appear in query results and dashboards all day, and incongruous
    -- ones make attendees distrust the data instead of learning from it.
    GET(ARRAY_CONSTRUCT('The Copper','Old Mill','Riverside','Market','Station','Harbour',
                        'Castle','Abbey','Bridge','Corner'), r1 % 10)::VARCHAR
      || ' ' ||
    GET(ARRAY_CONSTRUCT('Cafe','Bistro','Grill','Bakery','Deli','Pharmacy','Boutique',
                        'Hardware','Florist','Newsagent'), r2 % 10)::VARCHAR AS MERCHANT_NAME,
    GET(ARRAY_CONSTRUCT('Restaurant','Restaurant','Fast Food','Bakery','Fast Food',
                        'Pharmacy','Clothing','Hardware','Florist','Convenience'),
        r2 % 10)::VARCHAR AS MERCHANT_CATEGORY,
    CASE WHEN r2 % 100 < 85 THEN 'SMB'
         WHEN r2 % 100 < 97 THEN 'Mid-Market'
         ELSE 'Enterprise' END AS MERCHANT_SEGMENT,
    GET(ARRAY_CONSTRUCT('IE','FR','DE','NL','ES','IT','BE','AT','PT','GR'), r3 % 10)::VARCHAR AS COUNTRY_CODE,
    GET(ARRAY_CONSTRUCT('Ireland & France','Benelux','DACH','Southern Europe'), r3 % 4)::VARCHAR AS ACQUIRING_REGION,
    DATEADD(day, -(r1 % 1800), '2025-10-01'::DATE) AS ONBOARDED_DATE,
    1 + (r2 % 12) AS TERMINAL_COUNT
FROM gen;

-- 500,000 transactions across the same June to September 2025 window as day two.
CREATE OR REPLACE TABLE TRANSACTIONS AS
WITH gen AS (
    SELECT SEQ4() + 1 AS txn_seq,
           UNIFORM(1, 5000, RANDOM(21))     AS merchant_id,
           UNIFORM(0, 9999, RANDOM(22))     AS r_amount,
           UNIFORM(0, 121, RANDOM(23))      AS r_day,
           UNIFORM(0, 86399, RANDOM(24))    AS r_second,
           UNIFORM(0, 999, RANDOM(25))      AS r_result,
           UNIFORM(0, 999999, RANDOM(26))   AS r_misc
    FROM TABLE(GENERATOR(ROWCOUNT => 500000))
)
SELECT
    'T' || LPAD(txn_seq::VARCHAR, 9, '0')                          AS TRANSACTION_ID,
    merchant_id                                                    AS MERCHANT_ID,
    DATEADD(second, r_second, DATEADD(day, r_day, '2025-06-01'::DATE))::TIMESTAMP_NTZ
                                                                   AS TRANSACTION_TIMESTAMP,
    ROUND(2 + (r_amount / 100.0), 2)                               AS AMOUNT_EUR,
    'EUR'                                                          AS CURRENCY_CODE,
    CASE WHEN r_result < 940 THEN 'Approved'
         WHEN r_result < 990 THEN 'Declined'
         ELSE 'Referred' END                                       AS TRANSACTION_RESULT,
    GET(ARRAY_CONSTRUCT('Chip','Contactless','Magstripe','E-commerce','MOTO'),
        r_misc % 5)::VARCHAR                                       AS ENTRY_MODE,
    GET(ARRAY_CONSTRUCT('Visa','Mastercard','Amex'), r_misc % 3)::VARCHAR AS CARD_SCHEME
FROM gen;

SELECT 'MERCHANTS' AS tbl, COUNT(*) AS row_count FROM MERCHANTS
UNION ALL
SELECT 'TRANSACTIONS', COUNT(*) FROM TRANSACTIONS;
