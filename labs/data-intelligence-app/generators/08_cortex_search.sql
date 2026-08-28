-- Fiserv Snowcamp Workshop: two Cortex Search services.
--
-- Two services rather than one combined service, deliberately. It makes the
-- agent's Agentic Search genuinely multi-index and gives it a real routing
-- decision: rating-filtered questions belong to feedback, category and priority
-- questions belong to support cases.
--
-- MERCHANT_SEGMENT and ACQUIRING_REGION are carried as attributes so the agent can
-- answer "which merchant segments are most affected" directly from search results
-- without needing a join back to MERCHANTS.

USE ROLE ACCOUNTADMIN;
USE DATABASE FISERV_PAYMENTS_DB;
USE SCHEMA SEMANTIC;

CREATE OR REPLACE CORTEX SEARCH SERVICE MERCHANT_FEEDBACK_SEARCH
  ON FEEDBACK_TEXT
  ATTRIBUTES FEEDBACK_ID, MERCHANT_ID, DBA_NAME, FEEDBACK_DATE, RATING,
             FEEDBACK_THEME, MERCHANT_SEGMENT, ACQUIRING_REGION, COUNTRY_CODE, MCC_DESCRIPTION
  WAREHOUSE = FISERV_WH
  TARGET_LAG = '1 hour'
  COMMENT = 'Searchable merchant feedback with ratings and merchant context'
AS
SELECT
    f.FEEDBACK_TEXT,
    f.FEEDBACK_ID,
    f.MERCHANT_ID,
    m.DBA_NAME,
    f.FEEDBACK_DATE,
    f.RATING,
    f.FEEDBACK_THEME,
    m.MERCHANT_SEGMENT,
    m.ACQUIRING_REGION,
    m.COUNTRY_CODE,
    m.MCC_DESCRIPTION
FROM FISERV_PAYMENTS_DB.RAW.MERCHANT_FEEDBACK f
JOIN FISERV_PAYMENTS_DB.RAW.MERCHANTS m
  ON m.MERCHANT_ID = f.MERCHANT_ID;

CREATE OR REPLACE CORTEX SEARCH SERVICE SUPPORT_CASE_SEARCH
  ON CASE_TEXT
  ATTRIBUTES CASE_ID, MERCHANT_ID, DBA_NAME, OPENED_DATE, CASE_CATEGORY, PRIORITY,
             CASE_THEME, MERCHANT_SEGMENT, ACQUIRING_REGION, COUNTRY_CODE, MCC_DESCRIPTION
  WAREHOUSE = FISERV_WH
  TARGET_LAG = '1 hour'
  COMMENT = 'Searchable merchant support cases with category, priority and merchant context'
AS
SELECT
    c.CASE_TEXT,
    c.CASE_ID,
    c.MERCHANT_ID,
    m.DBA_NAME,
    c.OPENED_DATE,
    c.CASE_CATEGORY,
    c.PRIORITY,
    c.CASE_THEME,
    m.MERCHANT_SEGMENT,
    m.ACQUIRING_REGION,
    m.COUNTRY_CODE,
    m.MCC_DESCRIPTION
FROM FISERV_PAYMENTS_DB.RAW.SUPPORT_CASES c
JOIN FISERV_PAYMENTS_DB.RAW.MERCHANTS m
  ON m.MERCHANT_ID = c.MERCHANT_ID;

SHOW CORTEX SEARCH SERVICES IN SCHEMA FISERV_PAYMENTS_DB.SEMANTIC;
