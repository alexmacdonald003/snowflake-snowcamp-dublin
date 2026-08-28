-- Fiserv Snowcamp Workshop: Interactive Tables for low-latency point lookups.
--
-- Interactive tables require clustering keys, and the clustering key is what the
-- point lookup filters on. Note the WAREHOUSE clause is the table's REFRESH
-- warehouse and must be a standard warehouse; the interactive warehouse is what
-- you QUERY it with. Two serving patterns:
--   MERCHANT_TRANSACTION_ANALYTICS  one row per merchant, looked up by MERCHANT_ID
--   AUTH_LOOKUP                     one row per authorisation, looked up by AUTH_ID
--
-- The comparison table STD_AUTH_LOOKUP is created on purpose WITHOUT clustering,
-- on the standard warehouse. If it were clustered, partition pruning would make
-- the standard path fast and the whole comparison would collapse. Session 4 leans
-- on the concurrency difference rather than single-lookup latency, but the
-- unclustered baseline still matters.

USE ROLE ACCOUNTADMIN;
USE DATABASE FISERV_PAYMENTS_DB;
USE SCHEMA INTERACTIVE;

CREATE OR REPLACE INTERACTIVE TABLE MERCHANT_TRANSACTION_ANALYTICS
  TARGET_LAG = '1 hour'
  WAREHOUSE = FISERV_WH          -- refresh warehouse: must NOT be interactive
  CLUSTER BY (MERCHANT_ID)
  COMMENT = 'Per merchant transaction summary. Point lookup by MERCHANT_ID.'
AS
SELECT
    a.MERCHANT_ID,
    a.DBA_NAME,
    a.MERCHANT_SEGMENT,
    a.RISK_TIER,
    a.ACQUIRING_REGION,
    a.COUNTRY_CODE,
    a.MCC_DESCRIPTION,
    COUNT(*)                                                        AS AUTH_ATTEMPTS,
    COUNT_IF(a.AUTH_RESULT = 'Approved')                            AS APPROVED_COUNT,
    ROUND(100.0 * COUNT_IF(a.AUTH_RESULT = 'Approved') / COUNT(*), 2) AS APPROVAL_RATE_PCT,
    SUM(CASE WHEN a.AUTH_RESULT = 'Approved' THEN a.AUTH_AMOUNT END) AS PROCESSED_VOLUME_EUR,
    ROUND(SUM(CASE WHEN a.AUTH_RESULT = 'Approved' THEN a.AUTH_AMOUNT END)
          / NULLIF(COUNT_IF(a.AUTH_RESULT = 'Approved'), 0), 2)     AS AVERAGE_TICKET_EUR,
    COUNT_IF(a.CHARGEBACK_FLAG)                                     AS CHARGEBACK_COUNT,
    MIN(a.AUTH_DATE)                                                AS FIRST_AUTH_DATE,
    MAX(a.AUTH_DATE)                                                AS LAST_AUTH_DATE
FROM FISERV_PAYMENTS_DB.DYNAMIC_TABLES.ENRICHED_AUTHORISATIONS a
GROUP BY
    a.MERCHANT_ID, a.DBA_NAME, a.MERCHANT_SEGMENT, a.RISK_TIER,
    a.ACQUIRING_REGION, a.COUNTRY_CODE, a.MCC_DESCRIPTION;

CREATE OR REPLACE INTERACTIVE TABLE AUTH_LOOKUP
  TARGET_LAG = '1 hour'
  WAREHOUSE = FISERV_WH          -- refresh warehouse: must NOT be interactive
  CLUSTER BY (AUTH_ID)
  COMMENT = 'Per authorisation detail. Point lookup by AUTH_ID.'
AS
SELECT
    AUTH_ID,
    MERCHANT_ID,
    DBA_NAME,
    AUTH_TIMESTAMP,
    AUTH_DATE,
    AUTH_AMOUNT,
    AUTH_RESULT,
    DECLINE_REASON,
    ENTRY_MODE,
    CARD_SCHEME,
    CARD_BIN,
    PAYMENT_PRODUCT_NAME,
    ACQUIRING_REGION,
    COUNTRY_CODE,
    CHARGEBACK_FLAG,
    CHARGEBACK_REASON
FROM FISERV_PAYMENTS_DB.DYNAMIC_TABLES.ENRICHED_AUTHORISATIONS;

-- Deliberately unclustered standard table, for the comparison in session 4.
CREATE OR REPLACE TABLE STD_AUTH_LOOKUP
  COMMENT = 'Unclustered copy of AUTH_LOOKUP on standard storage. Baseline for the Interactive Tables comparison. Do not add clustering keys: it would invalidate the demo.'
AS
SELECT * FROM FISERV_PAYMENTS_DB.INTERACTIVE.AUTH_LOOKUP;

SHOW INTERACTIVE TABLES IN SCHEMA FISERV_PAYMENTS_DB.INTERACTIVE;
