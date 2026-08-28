-- Fiserv Snowcamp Workshop: semantic view for Cortex Analyst.
--
-- Four tables: two facts (authorisations, fee lines) and two dimensions
-- (merchants, payment products). Declaring FEE_LINES as a separate fact with a
-- relationship to AUTHORISATIONS is deliberate: it lets Snowflake resolve the
-- fan-out so that summing AUTH_AMOUNT is not inflated by the three fee lines per
-- authorisation. Getting this wrong is the single most likely cause of a
-- confidently wrong number in front of the room.
--
-- Comments matter here. Cortex Analyst reads them, and the two ambiguities that
-- would otherwise bite are called out explicitly:
--   * processed volume counts APPROVED authorisations only
--   * total fees includes pass-through interchange; net fee revenue does not

USE ROLE ACCOUNTADMIN;
USE DATABASE FISERV_PAYMENTS_DB;
USE SCHEMA SEMANTIC;

CREATE OR REPLACE SEMANTIC VIEW PAYMENTS_ANALYTICS

  TABLES (
    auths AS FISERV_PAYMENTS_DB.RAW.AUTHORISATIONS
      PRIMARY KEY (AUTH_ID)
      WITH SYNONYMS ('authorisations', 'transactions', 'payments', 'card transactions')
      COMMENT = 'One row per card authorisation attempt, June to September 2025',

    fees AS FISERV_PAYMENTS_DB.RAW.FEE_LINES
      PRIMARY KEY (FEE_LINE_ID)
      WITH SYNONYMS ('fees', 'fee lines', 'charges')
      COMMENT = 'Fee components per approved authorisation: interchange, scheme fee, acquirer margin, gateway fee',

    merchants AS FISERV_PAYMENTS_DB.RAW.MERCHANTS
      PRIMARY KEY (MERCHANT_ID)
      WITH SYNONYMS ('merchants', 'customers', 'businesses', 'accounts')
      COMMENT = 'Merchants accepting card payments across ten Eurozone countries',

    products AS FISERV_PAYMENTS_DB.RAW.PAYMENT_PRODUCTS
      PRIMARY KEY (PRODUCT_ID)
      WITH SYNONYMS ('payment products', 'acceptance channels', 'devices')
      COMMENT = 'Payment acceptance products merchants transact on'
  )

  RELATIONSHIPS (
    auths_to_merchants AS auths (MERCHANT_ID) REFERENCES merchants,
    auths_to_products  AS auths (PAYMENT_PRODUCT_ID) REFERENCES products,
    fees_to_auths      AS fees (AUTH_ID) REFERENCES auths
  )

  FACTS (
    auths.auth_amount AS AUTH_AMOUNT
      COMMENT = 'Authorised amount in EUR. NULL on a small number of records by design.',
    auths.is_approved AS IFF(AUTH_RESULT = 'Approved', 1, 0)
      COMMENT = 'One when the authorisation was approved, otherwise zero',
    auths.is_chargeback AS IFF(CHARGEBACK_FLAG, 1, 0)
      COMMENT = 'One when the authorisation was later charged back',
    fees.fee_amount AS FEE_AMOUNT_EUR
      COMMENT = 'Fee component amount in EUR',
    fees.acquirer_revenue_amount AS IFF(FEE_CATEGORY = 'Acquirer Revenue', FEE_AMOUNT_EUR, 0)
      COMMENT = 'Fee amount retained by the acquirer, excluding pass-through'
  )

  DIMENSIONS (
    auths.auth_date AS TO_DATE(AUTH_TIMESTAMP)
      WITH SYNONYMS ('date', 'transaction date', 'processing date')
      COMMENT = 'Calendar date of the authorisation',
    auths.auth_month AS DATE_TRUNC('month', AUTH_TIMESTAMP)
      WITH SYNONYMS ('month', 'monthly')
      COMMENT = 'Month of the authorisation. Data covers June to September 2025 only.',
    auths.auth_result AS AUTH_RESULT
      WITH SYNONYMS ('result', 'status', 'outcome')
      COMMENT = 'Approved, Declined or Referred',
    auths.decline_reason AS DECLINE_REASON
      WITH SYNONYMS ('decline reason', 'reason for decline', 'failure reason')
      COMMENT = 'Why the authorisation was declined. NULL when approved.',
    auths.entry_mode AS ENTRY_MODE
      WITH SYNONYMS ('entry mode', 'how the card was presented')
      COMMENT = 'Chip and PIN, Contactless, E-commerce, MOTO or Tap to Phone',
    auths.card_scheme AS CARD_SCHEME
      WITH SYNONYMS ('scheme', 'card network', 'network')
      COMMENT = 'Visa, Mastercard, Amex or Domestic',
    auths.chargeback_reason AS CHARGEBACK_REASON
      WITH SYNONYMS ('chargeback reason', 'dispute reason')
      COMMENT = 'Reason a chargeback was raised. NULL when there was no chargeback.',
    merchants.merchant_name AS DBA_NAME
      WITH SYNONYMS ('merchant', 'merchant name', 'business name', 'trading name')
      COMMENT = 'Merchant trading name',
    merchants.merchant_segment AS MERCHANT_SEGMENT
      WITH SYNONYMS ('segment', 'merchant size', 'tier')
      COMMENT = 'SMB, Mid-Market or Enterprise',
    merchants.risk_tier AS RISK_TIER
      WITH SYNONYMS ('risk', 'risk tier', 'risk rating')
      COMMENT = 'Low, Standard, Elevated or High',
    merchants.acquiring_region AS ACQUIRING_REGION
      WITH SYNONYMS ('region', 'acquiring region', 'area')
      COMMENT = 'Benelux, DACH, Southern Europe or Ireland and France',
    merchants.country_code AS COUNTRY_CODE
      WITH SYNONYMS ('country', 'market')
      COMMENT = 'Two letter country code. Ten Eurozone countries.',
    merchants.mcc AS MCC
      WITH SYNONYMS ('mcc', 'merchant category code')
      COMMENT = 'Four digit merchant category code',
    merchants.merchant_category AS MCC_DESCRIPTION
      WITH SYNONYMS ('category', 'vertical', 'industry', 'merchant category')
      COMMENT = 'Plain English description of the merchant category',
    products.payment_product AS PRODUCT_NAME
      WITH SYNONYMS ('product', 'payment product', 'device', 'terminal')
      COMMENT = 'Payment acceptance product name',
    products.payment_channel AS CHANNEL
      WITH SYNONYMS ('channel', 'acceptance channel')
      COMMENT = 'Card present, E-commerce or MOTO',
    fees.fee_type AS FEE_TYPE
      WITH SYNONYMS ('fee type', 'charge type')
      COMMENT = 'Interchange, Scheme Fee, Acquirer Margin or Gateway Fee',
    fees.fee_category AS FEE_CATEGORY
      WITH SYNONYMS ('fee category')
      COMMENT = 'Pass-through (paid on to issuer or scheme) or Acquirer Revenue (retained)'
  )

  METRICS (
    auths.processed_volume AS SUM(auths.auth_amount * auths.is_approved)
      WITH SYNONYMS ('processed volume', 'volume', 'TPV', 'total payment volume', 'revenue', 'sales')
      COMMENT = 'Total value of APPROVED authorisations in EUR. Declined and referred authorisations are excluded, because a declined transaction is never processed. Use this for any question about volume, value or throughput.',

    auths.transaction_count AS SUM(auths.is_approved)
      WITH SYNONYMS ('transaction count', 'approved transactions', 'number of transactions')
      COMMENT = 'Number of APPROVED authorisations',

    auths.auth_attempt_count AS COUNT(auths.AUTH_ID)
      WITH SYNONYMS ('authorisation attempts', 'attempts', 'total authorisations')
      COMMENT = 'Number of authorisation ATTEMPTS regardless of outcome. This is the denominator for approval rate. Do not confuse with transaction count, which counts approvals only.',

    auths.approval_rate AS 100.0 * SUM(auths.is_approved) / NULLIF(COUNT(auths.AUTH_ID), 0)
      WITH SYNONYMS ('approval rate', 'acceptance rate', 'auth rate', 'approval percentage')
      COMMENT = 'Approved authorisations as a percentage of all attempts. August 2025 is materially lower than other months.',

    auths.average_ticket AS SUM(auths.auth_amount * auths.is_approved) / NULLIF(SUM(auths.is_approved), 0)
      WITH SYNONYMS ('average ticket', 'average transaction value', 'ATV', 'average basket')
      COMMENT = 'Average value of an approved authorisation in EUR',

    auths.chargeback_count AS SUM(auths.is_chargeback)
      WITH SYNONYMS ('chargebacks', 'chargeback count', 'disputes')
      COMMENT = 'Number of authorisations later charged back',

    auths.chargeback_rate AS 100.0 * SUM(auths.is_chargeback) / NULLIF(SUM(auths.is_approved), 0)
      WITH SYNONYMS ('chargeback rate', 'dispute rate')
      COMMENT = 'Chargebacks as a percentage of approved authorisations',

    merchants.merchant_count AS COUNT(DISTINCT merchants.MERCHANT_ID)
      WITH SYNONYMS ('merchant count', 'number of merchants', 'how many merchants')
      COMMENT = 'Distinct merchants',

    fees.total_fees AS SUM(fees.fee_amount)
      WITH SYNONYMS ('total fees', 'all fees', 'gross fees')
      COMMENT = 'All fee components in EUR, INCLUDING pass-through interchange and scheme fees that are paid on to the issuer and card network. This is not acquirer revenue.',

    fees.net_fee_revenue AS SUM(fees.acquirer_revenue_amount)
      WITH SYNONYMS ('net fee revenue', 'acquirer revenue', 'net revenue', 'retained revenue', 'our revenue')
      COMMENT = 'Fee income the acquirer retains: acquirer margin plus gateway fees. Excludes pass-through interchange and scheme fees. Use this for any question about our revenue or earnings.'
  )

  COMMENT = 'Fiserv payments analytics: card authorisations, fees, merchants and acceptance products across ten Eurozone countries, June to September 2025';

SHOW SEMANTIC VIEWS IN SCHEMA FISERV_PAYMENTS_DB.SEMANTIC;
