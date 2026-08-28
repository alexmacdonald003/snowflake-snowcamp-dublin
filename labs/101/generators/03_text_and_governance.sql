-- Fiserv Snowcamp 101: text data for the Cortex Playground and AISQL module (session 3).
--
-- REUSES the day-two merchant feedback corpus rather than generating new text. That corpus
-- took three rounds of remediation to get right: out-of-window dates remapped, competitor
-- brand names replaced, embedded newlines stripped. Generating a fresh 101 corpus would mean
-- either repeating that work or shipping text with the same defects.
--
-- 300 rows, not 1200. Session 3 is 45 minutes and AISQL functions are charged per call. An
-- attendee running AI_CLASSIFY over the full corpus by accident should not be an incident.
--
-- Also creates the governance objects session 3 needs: a masking policy, a role to test it
-- with, and a column worth masking.

USE ROLE ACCOUNTADMIN;
USE DATABASE FISERV_101_DB;
USE SCHEMA GOVERNED;
USE WAREHOUSE FISERV_101_WH;

CREATE OR REPLACE TABLE MERCHANT_FEEDBACK AS
SELECT
    FEEDBACK_ID,
    MERCHANT_ID,
    FEEDBACK_DATE,
    RATING,
    FEEDBACK_THEME,
    FEEDBACK_TEXT,
    -- A plausible PII column so the masking module has something worth protecting. Derived,
    -- not real, and obviously synthetic on inspection.
    'contact' || LPAD(MOD(ABS(HASH(FEEDBACK_ID)), 9999)::VARCHAR, 4, '0')
      || '@merchant-example.com' AS CONTACT_EMAIL
FROM FISERV_PAYMENTS_DB.RAW.MERCHANT_FEEDBACK
SAMPLE (300 ROWS);

-- Session 3 RBAC: a role that should see feedback but never contact details.
CREATE ROLE IF NOT EXISTS FISERV_101_ANALYST;
GRANT USAGE ON DATABASE FISERV_101_DB TO ROLE FISERV_101_ANALYST;
GRANT USAGE ON ALL SCHEMAS IN DATABASE FISERV_101_DB TO ROLE FISERV_101_ANALYST;
GRANT SELECT ON ALL TABLES IN DATABASE FISERV_101_DB TO ROLE FISERV_101_ANALYST;
GRANT USAGE ON WAREHOUSE FISERV_101_WH TO ROLE FISERV_101_ANALYST;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE FISERV_101_ANALYST;
GRANT ROLE FISERV_101_ANALYST TO ROLE ACCOUNTADMIN;

-- Masking policy is CREATED here but deliberately NOT APPLIED. Applying it is the session 3
-- exercise: attendees see unmasked email, apply the policy themselves, switch role, and watch
-- the same query return something different. Pre-applying it removes the before-and-after.
CREATE MASKING POLICY IF NOT EXISTS EMAIL_MASK
  AS (val VARCHAR) RETURNS VARCHAR ->
    CASE
      WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'SYSADMIN') THEN val
      ELSE REGEXP_REPLACE(val, '^[^@]+', '****')
    END
  COMMENT = 'Masks the local part of an email address for roles other than ACCOUNTADMIN and SYSADMIN. Session 3 applies this to GOVERNED.MERCHANT_FEEDBACK.CONTACT_EMAIL.';

SELECT 'feedback rows' AS check_name, COUNT(*)::VARCHAR AS result FROM MERCHANT_FEEDBACK
UNION ALL
SELECT 'distinct themes', COUNT(DISTINCT FEEDBACK_THEME)::VARCHAR FROM MERCHANT_FEEDBACK
UNION ALL
SELECT 'contact_email present and unmasked',
       IFF(MAX(CONTACT_EMAIL) LIKE 'contact%@%', 'yes', 'no')
FROM MERCHANT_FEEDBACK;

-- There is no INFORMATION_SCHEMA.MASKING_POLICIES view, so confirm the policy separately.
-- One row expected, and it must NOT be attached to anything yet.
SHOW MASKING POLICIES LIKE 'EMAIL_MASK' IN SCHEMA FISERV_101_DB.GOVERNED;
