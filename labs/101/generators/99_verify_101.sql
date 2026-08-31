-- Fiserv Snowcamp Workshop: verify the day-one 101 environment.
--
--     EXECUTE IMMEDIATE FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/101/generators/99_verify_101.sql;
--
-- Every row must say PASS. If any row says FAIL, tell your facilitator the CHECK_NAME
-- before trying to fix it.
--
-- Thresholds, not exact counts, where a lab mutates the table. Part 1 deletes the DACH rows
-- from CATEGORY_BY_REGION to demonstrate Time Travel, taking it from 32 rows to 24, so an
-- exact check there would fail for anyone re-running this mid-session.

USE ROLE ACCOUNTADMIN;
USE DATABASE FISERV_101_DB;
USE WAREHOUSE FISERV_101_WH;

-- EXECUTE IMMEDIATE FROM returns only the LAST result set, so every check is collected
-- into one table and selected once at the end. Without this the attendee sees the final
-- check alone and assumes the rest never ran.
CREATE OR REPLACE TEMPORARY TABLE FISERV_101_DB.PUBLIC.VERIFY_RESULTS (
    CHECK_NAME STRING,
    ACTUAL     NUMBER,
    EXPECTED   NUMBER,
    STATUS     STRING
);

-- Warehouses and roles are account-level, so INFORMATION_SCHEMA cannot see them.
-- SHOW then RESULT_SCAN of the immediately preceding statement gives the same shape.
-- Part 1 compares a cold X-Small against a cold Small on a warehouse that has never
-- run anything, so all three of FISERV_101_WH, FISERV_101_BIG_WH and
-- FISERV_101_TIMING_WH have to exist or the first module loses its point.
SHOW WAREHOUSES LIKE 'FISERV_101%';
INSERT INTO FISERV_101_DB.PUBLIC.VERIFY_RESULTS
SELECT 'WAREHOUSES FISERV_101_WH + BIG_WH + TIMING_WH', COUNT(*), 3,
       IFF(COUNT(*) = 3, 'PASS', 'FAIL')
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

SHOW ROLES LIKE 'FISERV_101_ANALYST';
INSERT INTO FISERV_101_DB.PUBLIC.VERIFY_RESULTS
SELECT 'ROLE FISERV_101_ANALYST', COUNT(*), 1,
       IFF(COUNT(*) = 1, 'PASS', 'FAIL')
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- Data and schema checks.
INSERT INTO FISERV_101_DB.PUBLIC.VERIFY_RESULTS
SELECT 'RAW.MERCHANTS' AS CHECK_NAME,
       COUNT(*) AS ACTUAL, 5000 AS EXPECTED,
       IFF(COUNT(*) = 5000, 'PASS', 'FAIL') AS STATUS
FROM FISERV_101_DB.RAW.MERCHANTS
UNION ALL
SELECT 'RAW.TRANSACTIONS', COUNT(*), 500000,
       IFF(COUNT(*) = 500000, 'PASS', 'FAIL')
FROM FISERV_101_DB.RAW.TRANSACTIONS
UNION ALL
SELECT 'RAW.TERMINAL_TELEMETRY (JSON docs)', COUNT(*), 3000,
       IFF(COUNT(*) = 3000, 'PASS', 'FAIL')
FROM FISERV_101_DB.RAW.TERMINAL_TELEMETRY
UNION ALL
SELECT 'GOVERNED.MERCHANT_FEEDBACK', COUNT(*), 300,
       IFF(COUNT(*) = 300, 'PASS', 'FAIL')
FROM FISERV_101_DB.GOVERNED.MERCHANT_FEEDBACK
UNION ALL
-- Immutable reference copy, so this one is exact.
SELECT 'ANALYTICS.CATEGORY_BY_REGION_BACKUP', COUNT(*), 32,
       IFF(COUNT(*) = 32, 'PASS', 'FAIL')
FROM FISERV_101_DB.ANALYTICS.CATEGORY_BY_REGION_BACKUP
UNION ALL
-- Part 1 deletes DACH from this table, so 24 is a valid mid-session state.
SELECT 'ANALYTICS.CATEGORY_BY_REGION (>=24)', COUNT(*), 32,
       IFF(COUNT(*) >= 24, 'PASS', 'FAIL')
FROM FISERV_101_DB.ANALYTICS.CATEGORY_BY_REGION
UNION ALL
SELECT 'ANALYTICS.TERMINAL_EVENT_SUMMARY', COUNT(*), 18,
       IFF(COUNT(*) = 18, 'PASS', 'FAIL')
FROM FISERV_101_DB.ANALYTICS.TERMINAL_EVENT_SUMMARY
UNION ALL
SELECT 'SCHEMAS (RAW, ANALYTICS, GOVERNED)', COUNT(*), 3,
       IFF(COUNT(*) = 3, 'PASS', 'FAIL')
FROM FISERV_101_DB.INFORMATION_SCHEMA.SCHEMATA
WHERE SCHEMA_NAME IN ('RAW', 'ANALYTICS', 'GOVERNED')
UNION ALL
SELECT 'STAGES (PUBLIC_DATA_STAGE, TERMINAL_STAGE)', COUNT(*), 2,
       IFF(COUNT(*) = 2, 'PASS', 'FAIL')
FROM FISERV_101_DB.INFORMATION_SCHEMA.STAGES
WHERE STAGE_NAME IN ('PUBLIC_DATA_STAGE', 'TERMINAL_STAGE');

-- The one result set the attendee sees. FAIL sorts before PASS, so anything broken sits
-- at the top of the grid rather than buried in the middle.
SELECT CHECK_NAME, ACTUAL, EXPECTED, STATUS
FROM FISERV_101_DB.PUBLIC.VERIFY_RESULTS
ORDER BY STATUS, CHECK_NAME;
