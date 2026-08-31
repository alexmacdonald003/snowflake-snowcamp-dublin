-- Fiserv Snowcamp Workshop: load the text corpora from CSV.
--
-- This REPLACES the 06a-06d generation chain for attendee setup. The corpora were
-- generated once with AI_COMPLETE, cleaned over three passes, and exported to CSV. Loading
-- the CSVs instead of regenerating is the right call for the workshop for three reasons:
--
--   1. Deterministic. Every attendee gets identical text, so the planted August signals and
--      the search results behave the same on all 60 accounts. Regenerating would give each
--      attendee different text and some would not find the story.
--   2. Fast. Loading 2,400 rows takes seconds; generation took 85s of LLM calls per account.
--   3. Clean. The generated text needed three rounds of remediation (out-of-window dates,
--      competitor brand names, embedded newlines). Those fixes live in the CSV, not in a
--      prompt that might drift.
--
-- The 06a-06d scripts stay in the repo as the provenance of the data, not as setup steps.
--
-- STAGE_NAME is passed in by the orchestrator so this works from either a Git repository
-- stage or an internal stage without editing the file.

USE ROLE ACCOUNTADMIN;
USE DATABASE FISERV_PAYMENTS_DB;
USE SCHEMA RAW;

CREATE OR REPLACE FILE FORMAT CSV_IMPORT
  TYPE = CSV
  FIELD_DELIMITER = ','
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  EMPTY_FIELD_AS_NULL = TRUE
  COMPRESSION = NONE;

CREATE OR REPLACE TABLE MERCHANT_FEEDBACK (
    FEEDBACK_ID    VARCHAR,
    MERCHANT_ID    NUMBER,
    FEEDBACK_DATE  DATE,
    RATING         NUMBER,
    FEEDBACK_THEME VARCHAR,
    FEEDBACK_TEXT  VARCHAR
);

CREATE OR REPLACE TABLE SUPPORT_CASES (
    CASE_ID       VARCHAR,
    MERCHANT_ID   NUMBER,
    OPENED_DATE   DATE,
    CASE_CATEGORY VARCHAR,
    PRIORITY      VARCHAR,
    CASE_THEME    VARCHAR,
    CASE_TEXT     VARCHAR
);

-- COPY INTO <table> cannot read from a git repository stage: Snowflake rejects it with
-- "Unsupported feature 'Copy into table from Git Repository'". COPY FILES *can* read from one,
-- and the documented target is an internal named stage, so stage the CSVs first and load from
-- there. Two statements instead of one, and no PUT from a client, which matters because
-- attendees only have a browser.
CREATE STAGE IF NOT EXISTS FISERV_SETUP.PUBLIC.TEXT_CSV
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'Landing stage for the text corpora, copied from the git repository clone.';

COPY FILES
  INTO @FISERV_SETUP.PUBLIC.TEXT_CSV/
  FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/data/
  FILES = ('merchant_feedback.csv', 'support_cases.csv');

COPY INTO MERCHANT_FEEDBACK
  FROM @FISERV_SETUP.PUBLIC.TEXT_CSV/merchant_feedback.csv
  FILE_FORMAT = CSV_IMPORT
  ON_ERROR = ABORT_STATEMENT;

COPY INTO SUPPORT_CASES
  FROM @FISERV_SETUP.PUBLIC.TEXT_CSV/support_cases.csv
  FILE_FORMAT = CSV_IMPORT
  ON_ERROR = ABORT_STATEMENT;

-- Row counts must be exactly 1200 each. Anything else means the CSV was truncated or the
-- newline cleaning regressed, both of which would silently break the search modules.
SELECT 'MERCHANT_FEEDBACK' AS tbl, COUNT(*) AS rows_loaded,
       IFF(COUNT(*) = 1200, 'PASS', 'FAIL') AS status
FROM MERCHANT_FEEDBACK
UNION ALL
SELECT 'SUPPORT_CASES', COUNT(*),
       IFF(COUNT(*) = 1200, 'PASS', 'FAIL')
FROM SUPPORT_CASES;
