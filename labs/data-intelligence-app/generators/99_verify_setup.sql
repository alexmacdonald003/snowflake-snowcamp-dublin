-- Fiserv Snowcamp Workshop: verify the setup.
--
-- Run after 00_setup_all.sql. Every row must say PASS. This is the check the facilitator
-- runs across the room before day two starts, so it asserts the things that would silently
-- ruin a module rather than just counting objects:
--
--   * Exact row counts, because a short load looks like working data until a metric is wrong.
--   * The planted August dip, because it is the spine of both day-two sessions.
--   * The planted NULL defects, because the DMF exercise depends on them existing.
--   * The FEE_TYPE monitoring GAP still being a gap, because a helpful facilitator may have
--     "fixed" it and removed the exercise.
--   * Incremental refresh mode on the dynamic tables, because Snowflake silently falls back
--     to FULL on complex queries and the pipeline module teaches the difference.
--   * Interactive tables being clustered, because they cannot be created otherwise and an
--     unclustered baseline is what the concurrency demo compares against.

USE ROLE ACCOUNTADMIN;
USE DATABASE FISERV_PAYMENTS_DB;
USE WAREHOUSE FISERV_WH;

WITH checks AS (

    SELECT 'MERCHANTS row count' AS check_name,
           COUNT(*)::VARCHAR AS actual, '2000000' AS expected
    FROM RAW.MERCHANTS
    UNION ALL
    SELECT 'AUTHORISATIONS row count', COUNT(*)::VARCHAR, '10000000' FROM RAW.AUTHORISATIONS
    UNION ALL
    SELECT 'FEE_LINES row count', COUNT(*)::VARCHAR, '30253689' FROM RAW.FEE_LINES
    UNION ALL
    SELECT 'PAYMENT_PRODUCTS row count', COUNT(*)::VARCHAR, '10' FROM RAW.PAYMENT_PRODUCTS
    UNION ALL
    SELECT 'MERCHANT_FEEDBACK row count', COUNT(*)::VARCHAR, '1200' FROM RAW.MERCHANT_FEEDBACK
    UNION ALL
    SELECT 'SUPPORT_CASES row count', COUNT(*)::VARCHAR, '1200' FROM RAW.SUPPORT_CASES

    UNION ALL
    -- The story. August must be materially below the other three months.
    SELECT 'August approval dip present',
           IFF(ROUND(MIN(rate), 0) = 88 AND ROUND(MAX(rate), 0) = 94, 'yes', 'no'), 'yes'
    FROM (
        SELECT MONTH(AUTH_TIMESTAMP) AS m,
               COUNT_IF(AUTH_RESULT = 'Approved') * 100.0 / COUNT(*) AS rate
        FROM RAW.AUTHORISATIONS GROUP BY 1
    )
    UNION ALL
    SELECT 'Issuer Unavailable spike in August',
           IFF(COUNT(*) > 30000, 'yes', 'no'), 'yes'
    FROM RAW.AUTHORISATIONS
    WHERE MONTH(AUTH_TIMESTAMP) = 8 AND DECLINE_REASON = 'Issuer Unavailable'

    UNION ALL
    -- Planted data quality defects. The DMF module needs all three to exist.
    SELECT 'AUTH_AMOUNT NULLs planted', COUNT_IF(AUTH_AMOUNT IS NULL)::VARCHAR, '189'
    FROM RAW.AUTHORISATIONS
    UNION ALL
    SELECT 'FEE_AMOUNT_EUR NULLs planted', COUNT_IF(FEE_AMOUNT_EUR IS NULL)::VARCHAR, '215'
    FROM RAW.FEE_LINES
    UNION ALL
    SELECT 'FEE_TYPE NULLs planted', COUNT_IF(FEE_TYPE IS NULL)::VARCHAR, '152'
    FROM RAW.FEE_LINES

    UNION ALL
    -- The monitoring gap must still BE a gap. Two DMFs on FEE_LINES, neither on FEE_TYPE.
    SELECT 'FEE_TYPE still unmonitored (the exercise)',
           IFF(COUNT(*) = 0, 'yes', 'no'), 'yes'
    FROM TABLE(INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(
        REF_ENTITY_NAME => 'FISERV_PAYMENTS_DB.RAW.FEE_LINES', REF_ENTITY_DOMAIN => 'TABLE'))
    WHERE REF_ARGUMENTS ILIKE '%FEE_TYPE%'

    UNION ALL
    -- Derived objects.
    SELECT 'Dynamic tables built', COUNT(*)::VARCHAR, '5'
    FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = 'DYNAMIC_TABLES' AND IS_DYNAMIC = 'YES'
    UNION ALL
    SELECT 'Cortex Search services', COUNT(*)::VARCHAR, '2'
    FROM INFORMATION_SCHEMA.CORTEX_SEARCH_SERVICES
    UNION ALL
    SELECT 'Semantic view', COUNT(*)::VARCHAR, '1'
    FROM INFORMATION_SCHEMA.SEMANTIC_VIEWS
    UNION ALL
    SELECT 'Verified queries on semantic view',
           -- Count VERIFIED_AT, one per verified query. Counting 'QUESTION ' instead
           -- double-counts, because ONBOARDING_QUESTION also contains it.
           REGEXP_COUNT(GET_DDL('SEMANTIC_VIEW', 'SEMANTIC.PAYMENTS_ANALYTICS'), 'VERIFIED_AT')::VARCHAR,
           '5'
    UNION ALL
    SELECT 'Interactive tables clustered',
           COUNT_IF(CLUSTERING_KEY IS NOT NULL)::VARCHAR, '2'
    FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = 'INTERACTIVE' AND TABLE_NAME IN ('AUTH_LOOKUP', 'MERCHANT_TRANSACTION_ANALYTICS')
    UNION ALL
    SELECT 'Standard lookup baseline UNclustered (for the demo)',
           IFF(MAX(CLUSTERING_KEY) IS NULL, 'yes', 'no'), 'yes'
    FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = 'INTERACTIVE' AND TABLE_NAME = 'STD_AUTH_LOOKUP'
    UNION ALL
    -- POLICY_REFERENCES is a table FUNCTION, not a view. Query it by REF_ENTITY_NAME, not
    -- by POLICY_NAME: the POLICY_NAME form returns zero rows here even when the policy is
    -- demonstrably attached (ALTER TABLE ... ADD ROW ACCESS POLICY fails with 003549,
    -- "already has a ROW_ACCESS_POLICY"). Asking the table what is attached to it works.
    SELECT 'Row access policy applied', COUNT(*)::VARCHAR, '1'
    FROM TABLE(FISERV_PAYMENTS_DB.INFORMATION_SCHEMA.POLICY_REFERENCES(
        REF_ENTITY_NAME => 'FISERV_PAYMENTS_DB.RAW.MERCHANTS',
        REF_ENTITY_DOMAIN => 'TABLE'))
    WHERE POLICY_NAME = 'ACQUIRING_REGION_POLICY'
    UNION ALL
    -- Both search services the session-5 agent will bind to. The agent itself is NOT
    -- checked here: it does not exist yet, because building it is the session-5 exercise.
    SELECT 'Search services ready for session 5', COUNT(*)::VARCHAR, '2'
    FROM INFORMATION_SCHEMA.CORTEX_SEARCH_SERVICES
    WHERE SERVICE_NAME IN ('MERCHANT_FEEDBACK_SEARCH', 'SUPPORT_CASE_SEARCH')
)

SELECT check_name, expected, actual,
       IFF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY status DESC, check_name;
