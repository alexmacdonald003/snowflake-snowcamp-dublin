-- Fiserv Snowcamp Workshop: 3-tier Dynamic Tables pipeline.
--
-- Tier 1 refreshes on a 1 minute target lag; Tiers 2 and 3 use DOWNSTREAM so they
-- only refresh when their upstream changes. This is the structure session 4 walks
-- attendees through: "show me the pipeline status, target lag and row counts by tier".

USE ROLE ACCOUNTADMIN;
USE DATABASE FISERV_PAYMENTS_DB;
USE SCHEMA DYNAMIC_TABLES;

-- ---------------------------------------------------------------------------
-- Tier 1: enrich the two large source tables with merchant and product context.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE DYNAMIC TABLE ENRICHED_AUTHORISATIONS
  TARGET_LAG = '1 minute'
  WAREHOUSE = FISERV_WH
  REFRESH_MODE = INCREMENTAL
  COMMENT = 'Tier 1: authorisations enriched with merchant and payment product attributes'
AS
SELECT
    a.AUTH_ID,
    a.MERCHANT_ID,
    a.AUTH_TIMESTAMP,
    TO_DATE(a.AUTH_TIMESTAMP)           AS AUTH_DATE,
    a.AUTH_AMOUNT,
    a.CURRENCY_CODE,
    a.ENTRY_MODE,
    a.AUTH_RESULT,
    a.DECLINE_REASON,
    a.CARD_BIN,
    a.CARD_SCHEME,
    a.CHARGEBACK_FLAG,
    a.CHARGEBACK_REASON,
    m.DBA_NAME,
    m.MCC,
    m.MCC_DESCRIPTION,
    m.MERCHANT_SEGMENT,
    m.RISK_TIER,
    m.COUNTRY_CODE,
    m.ACQUIRING_REGION,
    p.PRODUCT_ID                        AS PAYMENT_PRODUCT_ID,
    p.PRODUCT_NAME                      AS PAYMENT_PRODUCT_NAME,
    p.CHANNEL                           AS PAYMENT_CHANNEL
FROM FISERV_PAYMENTS_DB.RAW.AUTHORISATIONS a
JOIN FISERV_PAYMENTS_DB.RAW.MERCHANTS m
  ON m.MERCHANT_ID = a.MERCHANT_ID
JOIN FISERV_PAYMENTS_DB.RAW.PAYMENT_PRODUCTS p
  ON p.PRODUCT_ID = a.PAYMENT_PRODUCT_ID;

CREATE OR REPLACE DYNAMIC TABLE ENRICHED_FEE_LINES
  TARGET_LAG = '1 minute'
  WAREHOUSE = FISERV_WH
  REFRESH_MODE = INCREMENTAL
  COMMENT = 'Tier 1: fee lines enriched with authorisation date and merchant context'
AS
SELECT
    f.FEE_LINE_ID,
    f.AUTH_ID,
    f.MERCHANT_ID,
    f.FEE_TYPE,
    f.FEE_CATEGORY,
    f.FEE_AMOUNT_EUR,
    f.FEE_BASIS_POINTS,
    f.CALCULATED_ON_AMOUNT,
    TO_DATE(a.AUTH_TIMESTAMP)           AS AUTH_DATE,
    a.ENTRY_MODE,
    a.CARD_SCHEME,
    a.PAYMENT_PRODUCT_ID,
    m.MERCHANT_SEGMENT,
    m.ACQUIRING_REGION,
    m.MCC
FROM FISERV_PAYMENTS_DB.RAW.FEE_LINES f
JOIN FISERV_PAYMENTS_DB.RAW.AUTHORISATIONS a
  ON a.AUTH_ID = f.AUTH_ID
JOIN FISERV_PAYMENTS_DB.RAW.MERCHANTS m
  ON m.MERCHANT_ID = f.MERCHANT_ID;

-- ---------------------------------------------------------------------------
-- Tier 2: transaction fact at fee line grain, joining the two Tier 1 tables.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE DYNAMIC TABLE FACT_TRANSACTIONS
  TARGET_LAG = DOWNSTREAM
  WAREHOUSE = FISERV_WH
  REFRESH_MODE = INCREMENTAL
  COMMENT = 'Tier 2: fee line grain fact combining authorisation and fee detail'
AS
SELECT
    f.FEE_LINE_ID,
    f.AUTH_ID,
    f.MERCHANT_ID,
    f.AUTH_DATE,
    f.FEE_TYPE,
    f.FEE_CATEGORY,
    f.FEE_AMOUNT_EUR,
    f.FEE_BASIS_POINTS,
    a.AUTH_AMOUNT,
    a.AUTH_RESULT,
    a.ENTRY_MODE,
    a.CARD_SCHEME,
    a.CHARGEBACK_FLAG,
    a.CHARGEBACK_REASON,
    a.DBA_NAME,
    a.MCC,
    a.MCC_DESCRIPTION,
    a.MERCHANT_SEGMENT,
    a.RISK_TIER,
    a.COUNTRY_CODE,
    a.ACQUIRING_REGION,
    a.PAYMENT_PRODUCT_NAME,
    a.PAYMENT_CHANNEL
FROM FISERV_PAYMENTS_DB.DYNAMIC_TABLES.ENRICHED_FEE_LINES f
JOIN FISERV_PAYMENTS_DB.DYNAMIC_TABLES.ENRICHED_AUTHORISATIONS a
  ON a.AUTH_ID = f.AUTH_ID;

-- ---------------------------------------------------------------------------
-- Tier 3: daily and product level aggregates.
-- Built from Tier 1 authorisations, not Tier 2, because authorisation-level
-- counts must not be inflated by the fee line fan-out.
--
-- Note on refresh mode: Snowflake's automatic selection picks FULL for the Tier 1
-- joins, which defeats the point of the module, so REFRESH_MODE = INCREMENTAL is
-- set explicitly there. Once Tier 1 is incremental, Tiers 2 and 3 follow, and all
-- five tables in this pipeline run INCREMENTAL - including these aggregates,
-- despite the COUNT(DISTINCT MERCHANT_ID).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE DYNAMIC TABLE DAILY_MERCHANT_METRICS
  TARGET_LAG = DOWNSTREAM
  WAREHOUSE = FISERV_WH
  COMMENT = 'Tier 3: one row per day. Approval rate and volume by processing date.'
AS
WITH auth_daily AS (
    SELECT
        AUTH_DATE,
        COUNT(*)                                                        AS AUTH_ATTEMPTS,
        COUNT_IF(AUTH_RESULT = 'Approved')                              AS APPROVED_COUNT,
        COUNT_IF(AUTH_RESULT = 'Declined')                              AS DECLINED_COUNT,
        COUNT_IF(AUTH_RESULT = 'Referred')                              AS REFERRED_COUNT,
        SUM(CASE WHEN AUTH_RESULT = 'Approved' THEN AUTH_AMOUNT END)    AS PROCESSED_VOLUME_EUR,
        COUNT_IF(CHARGEBACK_FLAG)                                       AS CHARGEBACK_COUNT,
        COUNT(DISTINCT MERCHANT_ID)                                     AS ACTIVE_MERCHANTS
    FROM FISERV_PAYMENTS_DB.DYNAMIC_TABLES.ENRICHED_AUTHORISATIONS
    GROUP BY AUTH_DATE
),
fee_daily AS (
    SELECT
        AUTH_DATE,
        SUM(FEE_AMOUNT_EUR)                                             AS TOTAL_FEES_EUR,
        SUM(CASE WHEN FEE_CATEGORY = 'Acquirer Revenue'
                 THEN FEE_AMOUNT_EUR END)                               AS NET_FEE_REVENUE_EUR
    FROM FISERV_PAYMENTS_DB.DYNAMIC_TABLES.ENRICHED_FEE_LINES
    GROUP BY AUTH_DATE
)
SELECT
    a.AUTH_DATE,
    a.AUTH_ATTEMPTS,
    a.APPROVED_COUNT,
    a.DECLINED_COUNT,
    a.REFERRED_COUNT,
    ROUND(100.0 * a.APPROVED_COUNT / NULLIF(a.AUTH_ATTEMPTS, 0), 2)     AS APPROVAL_RATE_PCT,
    a.PROCESSED_VOLUME_EUR,
    ROUND(a.PROCESSED_VOLUME_EUR / NULLIF(a.APPROVED_COUNT, 0), 2)      AS AVERAGE_TICKET_EUR,
    a.CHARGEBACK_COUNT,
    ROUND(100.0 * a.CHARGEBACK_COUNT / NULLIF(a.APPROVED_COUNT, 0), 4)  AS CHARGEBACK_RATE_PCT,
    a.ACTIVE_MERCHANTS,
    f.TOTAL_FEES_EUR,
    f.NET_FEE_REVENUE_EUR
FROM auth_daily a
LEFT JOIN fee_daily f
  ON f.AUTH_DATE = a.AUTH_DATE;

CREATE OR REPLACE DYNAMIC TABLE PAYMENT_PRODUCT_PERFORMANCE
  TARGET_LAG = DOWNSTREAM
  WAREHOUSE = FISERV_WH
  COMMENT = 'Tier 3: one row per payment product across the whole period'
AS
SELECT
    PAYMENT_PRODUCT_NAME,
    PAYMENT_CHANNEL,
    COUNT(*)                                                            AS AUTH_ATTEMPTS,
    COUNT_IF(AUTH_RESULT = 'Approved')                                  AS APPROVED_COUNT,
    ROUND(100.0 * COUNT_IF(AUTH_RESULT = 'Approved') / COUNT(*), 2)     AS APPROVAL_RATE_PCT,
    SUM(CASE WHEN AUTH_RESULT = 'Approved' THEN AUTH_AMOUNT END)        AS PROCESSED_VOLUME_EUR,
    ROUND(SUM(CASE WHEN AUTH_RESULT = 'Approved' THEN AUTH_AMOUNT END)
          / NULLIF(COUNT_IF(AUTH_RESULT = 'Approved'), 0), 2)           AS AVERAGE_TICKET_EUR,
    COUNT_IF(CHARGEBACK_FLAG)                                           AS CHARGEBACK_COUNT,
    ROUND(100.0 * COUNT_IF(CHARGEBACK_FLAG)
          / NULLIF(COUNT_IF(AUTH_RESULT = 'Approved'), 0), 4)           AS CHARGEBACK_RATE_PCT,
    COUNT(DISTINCT MERCHANT_ID)                                         AS ACTIVE_MERCHANTS
FROM FISERV_PAYMENTS_DB.DYNAMIC_TABLES.ENRICHED_AUTHORISATIONS
GROUP BY PAYMENT_PRODUCT_NAME, PAYMENT_CHANNEL;
