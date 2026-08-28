-- Fiserv Snowcamp Workshop: generate the two text corpora with AI_COMPLETE.
--
-- This script runs ONCE, on the build account. Its output is exported to CSV and
-- committed to the repo, so attendee accounts load fixed text via COPY INTO and
-- never call an LLM at setup. That keeps the data identical for everyone, costs
-- nothing at setup, and lets expected answers be pinned down.
--
-- Text is generated in batches of 25 to keep the number of LLM calls sensible.
-- Each batch gets a distinct angle hint so the output does not converge on a
-- single phrasing, which would make Cortex Search ranking look poor and flatten
-- AI_AGG theme summaries.

USE ROLE ACCOUNTADMIN;
USE DATABASE FISERV_PAYMENTS_DB;
USE SCHEMA RAW;
USE WAREHOUSE FISERV_BUILD_WH;

-- Angle hints cycle so each batch within a theme explores a different facet.
CREATE OR REPLACE TABLE GEN_ANGLES (angle_no NUMBER, angle_hint VARCHAR);
INSERT INTO GEN_ANGLES VALUES
  (0, 'written by a busy owner-operator, terse and slightly frustrated'),
  (1, 'written by a finance manager who is precise about amounts and dates'),
  (2, 'written by someone fairly new to card acceptance, asking rather than complaining'),
  (3, 'written by a multi-site operator comparing behaviour between locations'),
  (4, 'measured and professional, describing impact on the business'),
  (5, 'written after a repeat occurrence, referencing an earlier unresolved contact'),
  (6, 'brief and factual, almost a note to self'),
  (7, 'detailed and technical, mentioning specific terminal or checkout behaviour');

-- One row per batch of 25 records to generate.
CREATE OR REPLACE TABLE GEN_REQUESTS AS
WITH themes AS (
    SELECT 'FEEDBACK' AS corpus, 'settlement_delay'         AS theme, 180 AS target_count,
           'Merchant feedback about funds arriving later than expected in their bank account: delayed payouts, settlement landing a day or two late, cash flow strain, unclear settlement timing over weekends and public holidays.' AS subject,
           'low' AS rating_band
    UNION ALL SELECT 'FEEDBACK','terminal_reliability',200,
           'Merchant feedback about card terminals and checkout being unreliable: terminals timing out mid-payment, having to retry a card several times, customers walking out, connection dropping at busy periods.','low'
    UNION ALL SELECT 'FEEDBACK','fees_transparency',180,
           'Merchant feedback about card processing fees being hard to understand: unexpected charges on the monthly statement, not understanding interchange versus scheme fees versus the acquirer margin, wanting a clearer breakdown, querying a terminal or gateway charge.','mid'
    UNION ALL SELECT 'FEEDBACK','onboarding',150,
           'Merchant feedback about getting set up to take card payments: how long underwriting took, document requests, getting the terminal configured, going live faster or slower than promised.','mixed'
    UNION ALL SELECT 'FEEDBACK','support_responsiveness',150,
           'Merchant feedback about contacting support: hold times, being passed between teams, whether the issue was actually fixed, quality of the person who helped.','mixed'
    UNION ALL SELECT 'FEEDBACK','reporting',120,
           'Merchant feedback about reporting and the merchant dashboard: reconciling transactions to the bank, exporting data, finding a specific transaction, wanting better breakdowns by day or by till.','mixed'
    UNION ALL SELECT 'FEEDBACK','general_positive',220,
           'Positive merchant feedback about card acceptance working well: fast contactless, reliable terminal, easy to train staff on, good value, smooth day to day operation.','high'
    UNION ALL SELECT 'CASES','terminal_fault',260,
           'A support case log about a card terminal fault: device not connecting, card reader not responding, receipt printer failing, firmware or software version problems, device needing replacement or reconfiguration.','n/a'
    UNION ALL SELECT 'CASES','settlement_query',220,
           'A support case log about a settlement or payout query: an expected payout missing, an amount not matching the merchant expectation, a batch not settling, bank details or settlement schedule questions.','n/a'
    UNION ALL SELECT 'CASES','interchange_fee_query',200,
           'A support case log about a fee query: merchant challenging an interchange charge, asking why a card cost more than another, querying scheme fees or the acquirer margin, asking for a fee breakdown for a specific month.','n/a'
    UNION ALL SELECT 'CASES','chargeback_representment',180,
           'A support case log about a chargeback and representment: merchant disputing a chargeback, submitting evidence such as delivery proof or a signed receipt, asking about representment deadlines, escalation and pre-arbitration.','n/a'
    UNION ALL SELECT 'CASES','declined_transaction',200,
           'A support case log about declined transactions: an unusual number of declines, cards being refused that normally work, issuer not responding, do not honour responses, merchant asking whether the problem is on their side.','n/a'
    UNION ALL SELECT 'CASES','account_admin',140,
           'A support case log about account administration: changing contact details, adding a user, updating a business name, closing or adding a location, requesting a copy of a statement.','n/a'
),
batches AS (
    SELECT
        t.*,
        SEQ4() AS batch_no
    FROM themes t,
         TABLE(GENERATOR(ROWCOUNT => 12))          -- up to 12 batches per theme
    QUALIFY ROW_NUMBER() OVER (PARTITION BY t.corpus, t.theme ORDER BY SEQ4())
            <= CEIL(t.target_count / 25.0)
)
SELECT
    b.corpus,
    b.theme,
    b.target_count,
    b.rating_band,
    ROW_NUMBER() OVER (PARTITION BY b.corpus, b.theme ORDER BY b.batch_no) AS batch_no,
    -- The prompt. Delimiter-separated rather than JSON: fewer ways to fail to parse.
    'You are generating synthetic test data for a payments industry training workshop. '
    || 'The business is a European merchant acquirer serving small and medium businesses '
    || 'across Ireland, France, Germany, Austria, Netherlands, Belgium, Spain, Italy, Portugal and Greece. '
    || CASE b.corpus
         WHEN 'FEEDBACK' THEN 'Write 25 distinct pieces of merchant feedback, each 1 to 3 sentences, in the merchant''s own voice. '
         ELSE 'Write 25 distinct support case descriptions, each 1 to 3 sentences, written as a support agent''s case log. '
       END
    || 'Subject matter: ' || b.subject || ' '
    || 'Style for this batch: ' || a.angle_hint || '. '
    || 'Vary the wording, length and specifics heavily between items. Mention concrete details such as '
    || 'amounts in euros, times of day, days of the week, card schemes, terminal models or transaction counts where natural. '
    || 'Do not invent people''s names. Do not use the words Fiserv, Clover or Snowflake. '
    || 'Do not number the items. Do not add any preamble, heading or closing remark. '
    || 'Separate the 25 items with the exact delimiter ||| and nothing else.' AS prompt
FROM batches b
JOIN GEN_ANGLES a
  ON a.angle_no = MOD(b.batch_no, 8);

-- How many LLM calls this will make, and the expected yield.
SELECT
    corpus,
    COUNT(*)                    AS batches,
    COUNT(*) * 25               AS max_records,
    MAX(target_count)           AS target_per_theme
FROM GEN_REQUESTS
GROUP BY corpus
ORDER BY corpus;
