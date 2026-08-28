-- Fiserv Snowcamp Workshop: MERCHANTS (2,000,000 rows).
-- Replaces the upstream retail CUSTOMERS table. One row per merchant.
--
-- MERCHANT_ID is deliberately ordered by segment:
--   1 - 60,000          Enterprise   (3%)
--   60,001 - 300,000    Mid-Market   (12%)
--   300,001 - 2,000,000 SMB          (85%)
-- The authorisation generator selects merchants with a power-law skew toward low
-- IDs, so the Enterprise tail naturally dominates processed volume without
-- needing a separate weighting table.

USE ROLE ACCOUNTADMIN;
USE DATABASE FISERV_PAYMENTS_DB;
USE SCHEMA RAW;
USE WAREHOUSE FISERV_BUILD_WH;

CREATE OR REPLACE TABLE MERCHANTS AS
WITH base AS (
    SELECT
        SEQ8() + 1                                   AS merchant_id,
        UNIFORM(0, 999, RANDOM(101))                 AS r_country,
        UNIFORM(0, 999, RANDOM(102))                 AS r_mcc,
        UNIFORM(0, 999, RANDOM(103))                 AS r_risk,
        UNIFORM(0, 999, RANDOM(104))                 AS r_name_a,
        UNIFORM(0, 999, RANDOM(105))                 AS r_name_b,
        UNIFORM(0, 1094, RANDOM(106))                AS r_onboard_days
    FROM TABLE(GENERATOR(ROWCOUNT => 2000000))
),
typed AS (
    SELECT
        merchant_id,
        -- Segment derived from the ID range, so volume skew is reproducible.
        CASE
            WHEN merchant_id <= 60000  THEN 'Enterprise'
            WHEN merchant_id <= 300000 THEN 'Mid-Market'
            ELSE 'SMB'
        END AS merchant_segment,
        -- Country weighted by market size across the ten Eurozone countries.
        CASE
            WHEN r_country < 200 THEN 'DE'
            WHEN r_country < 380 THEN 'FR'
            WHEN r_country < 520 THEN 'IT'
            WHEN r_country < 650 THEN 'ES'
            WHEN r_country < 750 THEN 'NL'
            WHEN r_country < 810 THEN 'BE'
            WHEN r_country < 870 THEN 'IE'
            WHEN r_country < 920 THEN 'PT'
            WHEN r_country < 970 THEN 'AT'
            ELSE 'GR'
        END AS country_code,
        -- MCC weighted toward the Clover SMB long tail.
        CASE
            WHEN r_mcc < 180 THEN '5812'
            WHEN r_mcc < 330 THEN '5814'
            WHEN r_mcc < 450 THEN '5411'
            WHEN r_mcc < 570 THEN '7230'
            WHEN r_mcc < 680 THEN '8999'
            WHEN r_mcc < 780 THEN '5999'
            WHEN r_mcc < 850 THEN '5813'
            WHEN r_mcc < 900 THEN '5541'
            WHEN r_mcc < 955 THEN '5912'
            ELSE '7997'
        END AS mcc,
        r_risk,
        r_name_a,
        r_name_b,
        DATEADD(day, -r_onboard_days, DATE '2025-06-01') AS onboarded_date
    FROM base
)
SELECT
    merchant_id                                                     AS MERCHANT_ID,
    -- Trading name assembled from word lists; readable but clearly synthetic.
    GET(ARRAY_CONSTRUCT(
        'Kingsway','Harbour','Meridian','Northgate','Oakfield','Riverside','Stonebridge',
        'Cornerstone','Willow','Beacon','Falcon','Granary','Lantern','Marble','Nova',
        'Orchard','Pinnacle','Quayside','Rosewood','Summit','Thistle','Vantage','Westbrook',
        'Amber','Bluebell','Cedar','Dunmore','Elmwood','Fairview','Glenmore'
    ), r_name_a % 30)::VARCHAR
    || ' ' ||
    -- Suffix is chosen from the merchant's own vertical, so names stay consistent
    -- with MCC. Merchant names appear in agent answers and the dashboard, where a
    -- pharmacy called "Taproom" would undermine the data's credibility.
    GET(
        CASE mcc
            WHEN '5812' THEN ARRAY_CONSTRUCT('Kitchen','Bistro','Brasserie','Dining Room')
            WHEN '5814' THEN ARRAY_CONSTRUCT('Grill','Express','Takeaway','Burger Bar')
            WHEN '5411' THEN ARRAY_CONSTRUCT('Market','Provisions','Food Store','Grocers')
            WHEN '7230' THEN ARRAY_CONSTRUCT('Salon','Studio','Barbers','Beauty Room')
            WHEN '8999' THEN ARRAY_CONSTRUCT('Group','Services','Consulting','Partners')
            WHEN '5999' THEN ARRAY_CONSTRUCT('Boutique','Emporium','Trading','Supplies')
            WHEN '5813' THEN ARRAY_CONSTRUCT('Taproom','Wine Bar','Alehouse','Lounge')
            WHEN '5541' THEN ARRAY_CONSTRUCT('Fuel Stop','Service Station','Filling Station','Forecourt')
            WHEN '5912' THEN ARRAY_CONSTRUCT('Pharmacy','Chemist','Dispensary','Health Store')
            ELSE ARRAY_CONSTRUCT('Fitness','Gym','Wellness','Health Club')
        END,
        r_name_b % 4
    )::VARCHAR                                                      AS DBA_NAME,
    mcc                                                             AS MCC,
    CASE mcc
        WHEN '5812' THEN 'Eating Places and Restaurants'
        WHEN '5814' THEN 'Fast Food Restaurants'
        WHEN '5411' THEN 'Grocery Stores and Supermarkets'
        WHEN '7230' THEN 'Beauty and Barber Shops'
        WHEN '8999' THEN 'Professional Services'
        WHEN '5999' THEN 'Miscellaneous and Specialty Retail'
        WHEN '5813' THEN 'Drinking Places and Bars'
        WHEN '5541' THEN 'Service Stations and Fuel'
        WHEN '5912' THEN 'Drug Stores and Pharmacies'
        ELSE 'Health Clubs and Fitness'
    END                                                             AS MCC_DESCRIPTION,
    merchant_segment                                                AS MERCHANT_SEGMENT,
    -- Risk tier skews higher for e-commerce-leaning verticals and larger merchants.
    CASE
        WHEN r_risk < 520 THEN 'Low'
        WHEN r_risk < 830 THEN 'Standard'
        WHEN r_risk < 950 THEN 'Elevated'
        ELSE 'High'
    END                                                             AS RISK_TIER,
    country_code                                                    AS COUNTRY_CODE,
    -- Four acquiring regions. This is the row access policy dimension.
    CASE
        WHEN country_code IN ('NL','BE')           THEN 'Benelux'
        WHEN country_code IN ('DE','AT')           THEN 'DACH'
        WHEN country_code IN ('ES','IT','PT','GR') THEN 'Southern Europe'
        ELSE 'Ireland & France'
    END                                                             AS ACQUIRING_REGION,
    onboarded_date                                                  AS ONBOARDED_DATE,
    -- Terminal estate correlates with segment.
    CASE merchant_segment
        WHEN 'Enterprise' THEN UNIFORM(12, 40, RANDOM(107))
        WHEN 'Mid-Market' THEN UNIFORM(4, 12, RANDOM(108))
        ELSE UNIFORM(1, 3, RANDOM(109))
    END                                                             AS TERMINAL_COUNT
FROM typed;

-- Verification: segment mix should be roughly 85 / 12 / 3.
SELECT
    MERCHANT_SEGMENT,
    COUNT(*)                                                        AS merchant_count,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)                AS pct_of_total
FROM FISERV_PAYMENTS_DB.RAW.MERCHANTS
GROUP BY MERCHANT_SEGMENT
ORDER BY merchant_count DESC;
