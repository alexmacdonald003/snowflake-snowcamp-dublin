-- Fiserv Snowcamp Workshop: AUTHORISATIONS (10,000,000 rows).
-- Replaces the upstream retail ORDERS table. One row per card authorisation.
--
-- Three signals are planted deliberately, because the CoWork questions depend on
-- them being discoverable:
--   1. September 2025 is the volume peak (seasonal).
--   2. August 2025 has a depressed approval rate (~88% vs ~94% elsewhere), driven
--      by a spike in Issuer Unavailable and Do Not Honour declines. The merchant
--      feedback and support case corpora echo this, so Agentic Search can explain
--      what Cortex Analyst quantifies.
--   3. ~200 NULLs in AUTH_AMOUNT, which the Data Metric Function will catch.
--
-- Merchants are selected with a power-law skew toward low MERCHANT_IDs. Because
-- MERCHANTS is ordered Enterprise-first, this makes the Enterprise tail account
-- for roughly a third of authorisations off 3% of merchants.

USE ROLE ACCOUNTADMIN;
USE DATABASE FISERV_PAYMENTS_DB;
USE SCHEMA RAW;
USE WAREHOUSE FISERV_BUILD_WH;

CREATE OR REPLACE TABLE AUTHORISATIONS AS
WITH gen AS (
    SELECT
        SEQ8()                                                          AS rn,
        -- Power-law merchant selection: exponent 3 concentrates on low IDs.
        LEAST(2000000,
              FLOOR(POWER(UNIFORM(0::FLOAT, 1::FLOAT, RANDOM(201)), 3) * 2000000) + 1
        )::NUMBER                                                       AS merchant_id,
        UNIFORM(0, 999, RANDOM(202))                                    AS r_month,
        UNIFORM(0, 999, RANDOM(203))                                    AS r_result,
        UNIFORM(0, 999, RANDOM(204))                                    AS r_decline,
        UNIFORM(0, 999, RANDOM(205))                                    AS r_product,
        UNIFORM(0, 999, RANDOM(206))                                    AS r_scheme,
        UNIFORM(0, 9999, RANDOM(207))                                   AS r_amount,
        UNIFORM(0, 9999, RANDOM(208))                                   AS r_chargeback,
        UNIFORM(0, 999999, RANDOM(209))                                 AS r_null,
        UNIFORM(0, 86399, RANDOM(210))                                  AS r_second,
        UNIFORM(0, 99999, RANDOM(212))                                  AS r_day,
        UNIFORM(100000, 999999, RANDOM(211))                            AS r_bin
    FROM TABLE(GENERATOR(ROWCOUNT => 10000000))
),
dated AS (
    SELECT
        gen.*,
        -- Month weighted so September peaks: Jun 22%, Jul 24%, Aug 24%, Sep 30%.
        CASE
            WHEN r_month < 220 THEN DATE '2025-06-01'
            WHEN r_month < 460 THEN DATE '2025-07-01'
            WHEN r_month < 700 THEN DATE '2025-08-01'
            ELSE                     DATE '2025-09-01'
        END                                                             AS month_start,
        CASE
            WHEN r_month < 220 THEN 30
            WHEN r_month < 460 THEN 31
            WHEN r_month < 700 THEN 31
            ELSE                    30
        END                                                             AS days_in_month
    FROM gen
),
stamped AS (
    SELECT
        dated.*,
        -- UNIFORM requires constant bounds, so the day offset comes from a wide
        -- random reduced modulo the month length.
        DATEADD(second, r_second,
            DATEADD(day, r_day % days_in_month, month_start)
        )                                                               AS auth_timestamp,
        MONTH(month_start)                                              AS auth_month
    FROM dated
),
joined AS (
    SELECT
        s.*,
        m.mcc,
        m.merchant_segment,
        m.risk_tier
    FROM stamped s
    JOIN FISERV_PAYMENTS_DB.RAW.MERCHANTS m
      ON m.merchant_id = s.merchant_id
),
resolved AS (
    SELECT
        joined.*,
        -- The planted signal. August approval rate ~88%; other months ~94%.
        CASE
            WHEN auth_month = 8 THEN CASE WHEN r_result < 880 THEN 'Approved'
                                          WHEN r_result < 985 THEN 'Declined'
                                          ELSE 'Referred' END
            ELSE                     CASE WHEN r_result < 940 THEN 'Approved'
                                          WHEN r_result < 990 THEN 'Declined'
                                          ELSE 'Referred' END
        END                                                             AS auth_result,
        -- Product selection biased by vertical: service and fitness verticals lean
        -- e-commerce, hospitality and fuel lean card present.
        CASE
            WHEN mcc IN ('8999','7997','5999') THEN
                CASE WHEN r_product < 300 THEN 5
                     WHEN r_product < 520 THEN 6
                     WHEN r_product < 700 THEN 7
                     WHEN r_product < 820 THEN 8
                     WHEN r_product < 920 THEN 10
                     ELSE 3 END
            WHEN mcc = '5541' THEN
                CASE WHEN r_product < 700 THEN 9 ELSE 1 END
            ELSE
                CASE WHEN r_product < 380 THEN 1
                     WHEN r_product < 660 THEN 2
                     WHEN r_product < 850 THEN 3
                     WHEN r_product < 950 THEN 4
                     ELSE 5 END
        END                                                             AS payment_product_id
    FROM joined
)
SELECT
    UUID_STRING()                                                       AS AUTH_ID,
    merchant_id                                                         AS MERCHANT_ID,
    auth_timestamp                                                      AS AUTH_TIMESTAMP,
    -- Roughly 200 NULLs across 10M rows. The Data Metric Function catches these.
    CASE WHEN r_null < 20 THEN NULL
         ELSE ROUND(
            CASE mcc
                WHEN '5812' THEN 15  + (r_amount % 7500)  / 100.0
                WHEN '5814' THEN 5   + (r_amount % 2000)  / 100.0
                WHEN '5411' THEN 10  + (r_amount % 11000) / 100.0
                WHEN '7230' THEN 20  + (r_amount % 6000)  / 100.0
                WHEN '8999' THEN 50  + (r_amount % 45000) / 100.0
                WHEN '5999' THEN 15  + (r_amount % 18500) / 100.0
                WHEN '5813' THEN 8   + (r_amount % 5200)  / 100.0
                WHEN '5541' THEN 30  + (r_amount % 7000)  / 100.0
                WHEN '5912' THEN 5   + (r_amount % 5500)  / 100.0
                ELSE             20  + (r_amount % 7000)  / 100.0
            END, 2)
    END                                                                 AS AUTH_AMOUNT,
    'EUR'                                                               AS CURRENCY_CODE,
    CASE payment_product_id
        WHEN 1 THEN 'Chip & PIN'
        WHEN 2 THEN 'Contactless'
        WHEN 3 THEN 'Contactless'
        WHEN 4 THEN 'Tap to Phone'
        WHEN 8 THEN 'MOTO'
        WHEN 9 THEN 'Chip & PIN'
        ELSE 'E-commerce'
    END                                                                 AS ENTRY_MODE,
    auth_result                                                         AS AUTH_RESULT,
    -- Decline reasons. In August, issuer-side reasons dominate; this is the
    -- explanatory detail Agentic Search surfaces from the text corpora.
    CASE
        WHEN auth_result = 'Approved' THEN NULL
        WHEN auth_month = 8 THEN
            CASE WHEN r_decline < 380 THEN 'Issuer Unavailable'
                 WHEN r_decline < 680 THEN 'Do Not Honour'
                 WHEN r_decline < 790 THEN 'Insufficient Funds'
                 WHEN r_decline < 870 THEN 'Suspected Fraud'
                 WHEN r_decline < 940 THEN 'Expired Card'
                 ELSE 'Invalid CVV' END
        ELSE
            CASE WHEN r_decline < 420 THEN 'Insufficient Funds'
                 WHEN r_decline < 620 THEN 'Do Not Honour'
                 WHEN r_decline < 760 THEN 'Suspected Fraud'
                 WHEN r_decline < 870 THEN 'Expired Card'
                 WHEN r_decline < 950 THEN 'Invalid CVV'
                 ELSE 'Issuer Unavailable' END
    END                                                                 AS DECLINE_REASON,
    r_bin::VARCHAR                                                      AS CARD_BIN,
    CASE
        WHEN r_scheme < 480 THEN 'Visa'
        WHEN r_scheme < 850 THEN 'Mastercard'
        WHEN r_scheme < 930 THEN 'Amex'
        ELSE 'Domestic'
    END                                                                 AS CARD_SCHEME,
    payment_product_id                                                  AS PAYMENT_PRODUCT_ID,
    -- Chargebacks: ~0.4% of approved, weighted toward e-commerce and higher risk.
    CASE
        WHEN auth_result <> 'Approved' THEN FALSE
        WHEN payment_product_id IN (5,6,7,10) AND risk_tier IN ('Elevated','High')
             THEN r_chargeback < 180
        WHEN payment_product_id IN (5,6,7,10) THEN r_chargeback < 70
        WHEN risk_tier IN ('Elevated','High') THEN r_chargeback < 55
        ELSE r_chargeback < 18
    END                                                                 AS CHARGEBACK_FLAG,
    CASE
        WHEN auth_result <> 'Approved' THEN NULL
        WHEN NOT (
            CASE
                WHEN payment_product_id IN (5,6,7,10) AND risk_tier IN ('Elevated','High')
                     THEN r_chargeback < 180
                WHEN payment_product_id IN (5,6,7,10) THEN r_chargeback < 70
                WHEN risk_tier IN ('Elevated','High') THEN r_chargeback < 55
                ELSE r_chargeback < 18
            END
        ) THEN NULL
        WHEN r_chargeback % 4 = 0 THEN 'Fraud'
        WHEN r_chargeback % 4 = 1 THEN 'Product Not Received'
        WHEN r_chargeback % 4 = 2 THEN 'Duplicate Processing'
        ELSE 'Unrecognised Transaction'
    END                                                                 AS CHARGEBACK_REASON
FROM resolved;
