-- Fiserv Snowcamp Workshop: assemble MERCHANT_FEEDBACK and SUPPORT_CASES.
-- Trims each theme to its target count and attaches merchants, dates, ratings and
-- categories. The date and merchant skews here are what make the CoWork questions
-- answerable:
--   * terminal_reliability / terminal_fault / declined_transaction concentrate in
--     August, matching the planted approval-rate dip in AUTHORISATIONS.
--   * chargeback_representment is restricted to Mid-Market and Enterprise
--     merchants, so "which merchant segments are most affected" has a real answer.

USE ROLE ACCOUNTADMIN;
USE DATABASE FISERV_PAYMENTS_DB;
USE SCHEMA RAW;
USE WAREHOUSE FISERV_BUILD_WH;

CREATE OR REPLACE TABLE MERCHANT_FEEDBACK AS
WITH cleaned AS (
    -- Snowflake TRIM only strips spaces, so newlines survive SPLIT_TO_TABLE.
    -- Collapse every whitespace run to a single space, then remap the handful of
    -- month references the model produced that fall outside the June-September
    -- window the data actually covers.
    SELECT
        corpus, theme, rating_band, theme_rank,
        TRIM(REGEXP_REPLACE(
          REGEXP_REPLACE(
            REGEXP_REPLACE(
              REGEXP_REPLACE(
                REGEXP_REPLACE(
                  REGEXP_REPLACE(
                    REGEXP_REPLACE(
                      REGEXP_REPLACE(
                        REGEXP_REPLACE(item_text, '[Jj]anuary|[Ff]ebruary|[Mm]arch', 'June'),
                        '[Aa]pril', 'July'),
                      '[Oo]ctober|[Nn]ovember|[Dd]ecember', 'September'),
                    'Q1|Q2|Q4', 'Q3'),
                  -- Hardware brands are remapped onto the Clover product line so the
                  -- text stays consistent with PAYMENT_PRODUCTS.
                  '[Vv]erifone[ ]?[A-Za-z0-9/-]*', 'Clover Station Duo'),
                '[Ii]ngenico[ ]?[A-Za-z0-9/-]*', 'Clover Flex'),
              '[Pp]ax[ ]?[A-Z][0-9]{3}', 'Clover Mini'),
            -- Competing acquirers and PSPs are neutralised rather than named.
            '[Ss]um[Uu]p|[Zz]ettle|[Ss]quare [Rr]eader|[Ww]orldpay|[Aa]dyen|[Ss]tripe|[Ii]zettle',
            'our previous provider'),
          '\\s+', ' ')) AS item_text
    FROM GEN_ITEMS
),
trimmed AS (
    SELECT g.theme, g.rating_band, g.item_text, g.theme_rank,
           r.target_count,
           ABS(HASH(g.item_text, 11)) % 1000000 AS h1,
           ABS(HASH(g.item_text, 12)) % 1000000 AS h2,
           ABS(HASH(g.item_text, 13)) % 1000000 AS h3
    FROM cleaned g
    JOIN (SELECT DISTINCT corpus, theme, target_count FROM GEN_REQUESTS) r
      ON r.corpus = g.corpus AND r.theme = g.theme
    WHERE g.corpus = 'FEEDBACK'
      AND g.theme_rank <= r.target_count
),
dated AS (
    SELECT
        trimmed.*,
        -- Terminal reliability complaints cluster in August: half land there.
        CASE
            WHEN theme = 'terminal_reliability' THEN
                CASE WHEN h1 % 100 < 50 THEN DATE '2025-08-01'
                     WHEN h1 % 100 < 68 THEN DATE '2025-06-01'
                     WHEN h1 % 100 < 84 THEN DATE '2025-07-01'
                     ELSE                     DATE '2025-09-01' END
            ELSE
                CASE WHEN h1 % 100 < 25 THEN DATE '2025-06-01'
                     WHEN h1 % 100 < 50 THEN DATE '2025-07-01'
                     WHEN h1 % 100 < 75 THEN DATE '2025-08-01'
                     ELSE                     DATE '2025-09-01' END
        END AS month_start
    FROM trimmed
)
SELECT
    'FB-' || LPAD(ROW_NUMBER() OVER (ORDER BY theme, theme_rank)::VARCHAR, 6, '0') AS FEEDBACK_ID,
    -- Power-law merchant selection, matching AUTHORISATIONS, so feedback comes
    -- from merchants that actually transact.
    LEAST(2000000, FLOOR(POWER((h2 / 1000000.0), 3) * 2000000) + 1)::NUMBER        AS MERCHANT_ID,
    DATEADD(day, h3 % 28, month_start)                                            AS FEEDBACK_DATE,
    CASE rating_band
        WHEN 'low'  THEN 1 + (h3 % 2)          -- 1-2
        WHEN 'mid'  THEN 2 + (h3 % 2)          -- 2-3
        WHEN 'high' THEN 4 + (h3 % 2)          -- 4-5
        ELSE             1 + (h3 % 5)          -- 1-5
    END                                                                           AS RATING,
    theme                                                                         AS FEEDBACK_THEME,
    item_text                                                                     AS FEEDBACK_TEXT
FROM dated;

CREATE OR REPLACE TABLE SUPPORT_CASES AS
WITH cleaned AS (
    -- Same whitespace and month normalisation as MERCHANT_FEEDBACK.
    SELECT
        corpus, theme, theme_rank,
        TRIM(REGEXP_REPLACE(
          REGEXP_REPLACE(
            REGEXP_REPLACE(
              REGEXP_REPLACE(
                REGEXP_REPLACE(
                  REGEXP_REPLACE(
                    REGEXP_REPLACE(
                      REGEXP_REPLACE(
                        REGEXP_REPLACE(item_text, '[Jj]anuary|[Ff]ebruary|[Mm]arch', 'June'),
                        '[Aa]pril', 'July'),
                      '[Oo]ctober|[Nn]ovember|[Dd]ecember', 'September'),
                    'Q1|Q2|Q4', 'Q3'),
                  -- Hardware brands are remapped onto the Clover product line so the
                  -- text stays consistent with PAYMENT_PRODUCTS.
                  '[Vv]erifone[ ]?[A-Za-z0-9/-]*', 'Clover Station Duo'),
                '[Ii]ngenico[ ]?[A-Za-z0-9/-]*', 'Clover Flex'),
              '[Pp]ax[ ]?[A-Z][0-9]{3}', 'Clover Mini'),
            -- Competing acquirers and PSPs are neutralised rather than named.
            '[Ss]um[Uu]p|[Zz]ettle|[Ss]quare [Rr]eader|[Ww]orldpay|[Aa]dyen|[Ss]tripe|[Ii]zettle',
            'our previous provider'),
          '\\s+', ' ')) AS item_text
    FROM GEN_ITEMS
),
trimmed AS (
    SELECT g.theme, g.item_text, g.theme_rank,
           r.target_count,
           ABS(HASH(g.item_text, 21)) % 1000000 AS h1,
           ABS(HASH(g.item_text, 22)) % 1000000 AS h2,
           ABS(HASH(g.item_text, 23)) % 1000000 AS h3
    FROM cleaned g
    JOIN (SELECT DISTINCT corpus, theme, target_count FROM GEN_REQUESTS) r
      ON r.corpus = g.corpus AND r.theme = g.theme
    WHERE g.corpus = 'CASES'
      AND g.theme_rank <= r.target_count
),
dated AS (
    SELECT
        trimmed.*,
        -- Terminal faults and declined-transaction investigations cluster in August.
        CASE
            WHEN theme IN ('terminal_fault', 'declined_transaction') THEN
                CASE WHEN h1 % 100 < 52 THEN DATE '2025-08-01'
                     WHEN h1 % 100 < 68 THEN DATE '2025-06-01'
                     WHEN h1 % 100 < 84 THEN DATE '2025-07-01'
                     ELSE                     DATE '2025-09-01' END
            ELSE
                CASE WHEN h1 % 100 < 25 THEN DATE '2025-06-01'
                     WHEN h1 % 100 < 50 THEN DATE '2025-07-01'
                     WHEN h1 % 100 < 75 THEN DATE '2025-08-01'
                     ELSE                     DATE '2025-09-01' END
        END AS month_start
    FROM trimmed
)
SELECT
    'CS-' || LPAD(ROW_NUMBER() OVER (ORDER BY theme, theme_rank)::VARCHAR, 6, '0') AS CASE_ID,
    -- Representment cases are restricted to Mid-Market and Enterprise merchants
    -- (MERCHANT_ID <= 300000), which is what gives the segment question an answer.
    CASE
        WHEN theme = 'chargeback_representment'
            THEN (1 + (h2 % 300000))::NUMBER
        ELSE LEAST(2000000, FLOOR(POWER((h2 / 1000000.0), 3) * 2000000) + 1)::NUMBER
    END                                                                           AS MERCHANT_ID,
    DATEADD(day, h3 % 28, month_start)                                            AS OPENED_DATE,
    CASE theme
        WHEN 'terminal_fault'           THEN 'Terminal Fault'
        WHEN 'settlement_query'         THEN 'Settlement Query'
        WHEN 'interchange_fee_query'    THEN 'Fee Query'
        WHEN 'chargeback_representment' THEN 'Chargeback Representment'
        WHEN 'declined_transaction'     THEN 'Declined Transaction'
        ELSE                                 'Account Administration'
    END                                                                           AS CASE_CATEGORY,
    -- Anything stopping a merchant taking payment is treated as higher priority.
    CASE
        WHEN theme IN ('terminal_fault', 'declined_transaction') THEN
            CASE WHEN h3 % 100 < 35 THEN 'P1 - Critical' ELSE 'P2 - High' END
        WHEN theme IN ('settlement_query', 'chargeback_representment') THEN
            CASE WHEN h3 % 100 < 25 THEN 'P2 - High' ELSE 'P3 - Medium' END
        ELSE
            CASE WHEN h3 % 100 < 30 THEN 'P3 - Medium' ELSE 'P4 - Low' END
    END                                                                           AS PRIORITY,
    theme                                                                         AS CASE_THEME,
    item_text                                                                     AS CASE_TEXT
FROM dated;

-- Verification: counts, and whether the August clustering actually landed.
SELECT 'MERCHANT_FEEDBACK' AS table_name, COUNT(*) AS row_count,
       ROUND(AVG(RATING), 2) AS avg_rating
FROM MERCHANT_FEEDBACK
UNION ALL
SELECT 'SUPPORT_CASES', COUNT(*), NULL FROM SUPPORT_CASES;
