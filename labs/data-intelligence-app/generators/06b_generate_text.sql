-- Fiserv Snowcamp Workshop: run the AI_COMPLETE generation and flatten to records.
-- Runs ONCE on the build account. Output is exported to CSV for the repo.

USE ROLE ACCOUNTADMIN;
USE DATABASE FISERV_PAYMENTS_DB;
USE SCHEMA RAW;
USE WAREHOUSE FISERV_BUILD_WH;

-- One LLM call per batch. Snowflake parallelises these across the warehouse.
-- IF NOT EXISTS deliberately: re-running this file must not regenerate the text,
-- because the committed CSV and every derived expected value depend on it.
CREATE TABLE IF NOT EXISTS GEN_RAW AS
SELECT
    corpus,
    theme,
    rating_band,
    batch_no,
    AI_COMPLETE('claude-sonnet-4-5', prompt) AS response_text
FROM GEN_REQUESTS;

-- Split on the delimiter and clean up. Anything too short to be a real record is
-- discarded rather than trusted.
CREATE OR REPLACE TABLE GEN_ITEMS AS
SELECT
    corpus,
    theme,
    rating_band,
    batch_no,
    TRIM(REGEXP_REPLACE(s.value::VARCHAR, '^[\\s\\-\\*0-9\\.\\)]+', '')) AS item_text,
    ROW_NUMBER() OVER (PARTITION BY corpus, theme ORDER BY batch_no, s.index) AS theme_rank
FROM GEN_RAW,
     -- AI_COMPLETE returns VARIANT, so cast before splitting.
     LATERAL SPLIT_TO_TABLE(RESPONSE_TEXT::VARCHAR, '|||') s
WHERE LENGTH(TRIM(s.value::VARCHAR)) >= 40;

-- Yield check: did every theme produce at least its target count?
SELECT
    g.corpus,
    g.theme,
    r.target_count,
    COUNT(*)                                        AS generated,
    CASE WHEN COUNT(*) >= r.target_count THEN 'OK' ELSE 'SHORT' END AS yield_status,
    ROUND(AVG(LENGTH(g.item_text)))                 AS avg_chars,
    COUNT(DISTINCT g.item_text)                     AS distinct_texts
FROM GEN_ITEMS g
JOIN (SELECT DISTINCT corpus, theme, target_count FROM GEN_REQUESTS) r
  ON r.corpus = g.corpus AND r.theme = g.theme
GROUP BY g.corpus, g.theme, r.target_count
ORDER BY g.corpus, yield_status, g.theme;
