-- Fiserv Snowcamp Workshop: FEE_LINES (~30,000,000 rows).
-- Replaces the upstream retail ORDER_ITEMS table. Several fee components per
-- authorisation, which preserves the fan-out that the 3-tier Dynamic Tables
-- pipeline and the Interactive Tables grain depend on.
--
-- Fees accrue only on APPROVED authorisations: a declined authorisation incurs no
-- interchange. This is both correct and a useful teaching point.
--
-- Fee structure:
--   Interchange     0.20% debit / 0.30% credit (EU regulated caps)  Pass-through
--   Scheme Fee      2-5 bps                                          Pass-through
--   Acquirer Margin 30-50 bps                                        Acquirer Revenue
--   Gateway Fee     fixed EUR 0.02-0.05, e-commerce and MOTO only    Acquirer Revenue
--
-- Two injected defects, matching the upstream positions exactly:
--   FEE_AMOUNT_EUR  ~200 NULLs  -> caught by the Data Metric Function
--   FEE_TYPE        ~150 NULLs  -> NOT caught, because the DMF is attached to
--                                  FEE_CATEGORY instead. This gap is the exercise.

USE ROLE ACCOUNTADMIN;
USE DATABASE FISERV_PAYMENTS_DB;
USE SCHEMA RAW;
USE WAREHOUSE FISERV_BUILD_WH;

CREATE OR REPLACE TABLE FEE_LINES AS
WITH approved AS (
    SELECT
        AUTH_ID,
        MERCHANT_ID,
        AUTH_AMOUNT,
        PAYMENT_PRODUCT_ID,
        -- Card funding type is not held on the authorisation, so it is derived
        -- here purely to drive the regulated interchange rate.
        CASE WHEN ABS(HASH(AUTH_ID)) % 100 < 60 THEN 'Debit' ELSE 'Credit' END AS funding_type,
        ABS(HASH(AUTH_ID, 1)) % 1000000                                        AS h1,
        ABS(HASH(AUTH_ID, 2)) % 1000000                                        AS h2
    FROM FISERV_PAYMENTS_DB.RAW.AUTHORISATIONS
    WHERE AUTH_RESULT = 'Approved'
      AND AUTH_AMOUNT IS NOT NULL
),
lines AS (
    -- Interchange: regulated cap, pass-through to the issuer.
    SELECT AUTH_ID, MERCHANT_ID, AUTH_AMOUNT, h1, h2,
           'Interchange'                                     AS fee_type,
           'Pass-through'                                    AS fee_category,
           CASE funding_type WHEN 'Debit' THEN 20 ELSE 30 END AS basis_points,
           1                                                 AS line_seq
    FROM approved

    UNION ALL
    -- Scheme fee: pass-through to the card network.
    SELECT AUTH_ID, MERCHANT_ID, AUTH_AMOUNT, h1, h2,
           'Scheme Fee'                                      AS fee_type,
           'Pass-through'                                    AS fee_category,
           2 + (h1 % 4)                                      AS basis_points,
           2                                                 AS line_seq
    FROM approved

    UNION ALL
    -- Acquirer margin: this is revenue Fiserv retains.
    SELECT AUTH_ID, MERCHANT_ID, AUTH_AMOUNT, h1, h2,
           'Acquirer Margin'                                 AS fee_type,
           'Acquirer Revenue'                                AS fee_category,
           30 + (h2 % 21)                                    AS basis_points,
           3                                                 AS line_seq
    FROM approved

    UNION ALL
    -- Gateway fee: fixed, and only on card-not-present products.
    SELECT AUTH_ID, MERCHANT_ID, AUTH_AMOUNT, h1, h2,
           'Gateway Fee'                                     AS fee_type,
           'Acquirer Revenue'                                AS fee_category,
           NULL                                              AS basis_points,
           4                                                 AS line_seq
    FROM approved
    WHERE PAYMENT_PRODUCT_ID IN (5, 6, 7, 8, 10)
),
defect_ranked AS (
    -- EXACT, REPRODUCIBLE DEFECT COUNTS.
    --
    -- The original injection tested a hash of AUTH_ID (h1 < 16, h2 < 22). That is
    -- deterministic for a given AUTH_ID, but AUTH_ID is UUID_STRING(), which is
    -- regenerated on every build. So the counts drifted: a rebuild produced 190 and 123
    -- instead of 215 and 152, and all 60 attendee accounts would have differed from each
    -- other and from the lab notes.
    --
    -- Ranking within the affected line_seq and taking the first N gives EXACTLY N NULLs on
    -- every account. The ordering is by AUTH_ID, which is a random UUID, so the defects are
    -- still scattered randomly through the table rather than clustered in one merchant or
    -- one month. What is fixed is the count, not the rows, which is what the lab and the
    -- verification script actually depend on.
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY line_seq ORDER BY AUTH_ID) AS defect_rank
    FROM lines
)
SELECT
    UUID_STRING()                                                       AS FEE_LINE_ID,
    AUTH_ID                                                             AS AUTH_ID,
    MERCHANT_ID                                                         AS MERCHANT_ID,
    -- Exactly 152 NULLs. Deliberately NOT covered by a Data Metric Function: finding these
    -- is the session-4 exercise.
    CASE WHEN line_seq = 2 AND defect_rank <= 152 THEN NULL ELSE fee_type END AS FEE_TYPE,
    fee_category                                                        AS FEE_CATEGORY,
    -- Exactly 215 NULLs. Covered by a Data Metric Function, so these are detected.
    CASE
        WHEN line_seq = 3 AND defect_rank <= 215 THEN NULL
        WHEN fee_type = 'Gateway Fee' THEN ROUND(0.02 + (h1 % 4) / 100.0, 4)
        ELSE ROUND(AUTH_AMOUNT * basis_points / 10000.0, 4)
    END                                                                 AS FEE_AMOUNT_EUR,
    basis_points                                                        AS FEE_BASIS_POINTS,
    AUTH_AMOUNT                                                         AS CALCULATED_ON_AMOUNT
FROM defect_ranked;

-- Verification: fan-out, fee mix and the two injected defects.
SELECT
    FEE_TYPE,
    FEE_CATEGORY,
    COUNT(*)                                                            AS fee_lines,
    COUNT_IF(FEE_AMOUNT_EUR IS NULL)                                    AS null_amounts,
    ROUND(SUM(FEE_AMOUNT_EUR) / 1e6, 2)                                 AS total_fees_eur_m
FROM FISERV_PAYMENTS_DB.RAW.FEE_LINES
GROUP BY 1, 2
ORDER BY fee_lines DESC;
