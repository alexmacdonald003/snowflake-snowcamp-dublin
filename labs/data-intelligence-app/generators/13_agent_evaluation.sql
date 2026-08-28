-- Fiserv Snowcamp Workshop: agent evaluation set.
--
-- Every expected answer below was DERIVED BY QUERY against the built data, not
-- asserted from design intent. That distinction caught two wrong answer keys during
-- construction:
--   * "Enterprise drives the most volume" was wrong. SMB does, at EUR 216.5M.
--     Enterprise is the most CONCENTRATED (3% of merchants, 31% of volume) which is a
--     different claim, and an eval that conflated the two would have marked a correct
--     agent answer as a failure.
--   * The settlement-feedback count was 134, not the 180 carried in earlier notes.
--
-- Questions 1, 2, 4, 5 and 6 are analytical and have exact numeric answers.
-- Question 3 is a search question: the ground truth is qualitative on purpose,
-- because an exact hit count is brittle against a semantic index that legitimately
-- re-ranks. Question 7 is the cross-modal capstone.
--
-- Q2 and Q6 are traps. Q2 fails if the agent reports total fees (EUR 3,203,738.89)
-- as revenue. Q6 fails if the agent answers Enterprise from the concentration story.

-- BASELINE SCORES, run 'baseline-2', verified:
--   answer_correctness       1.000   0 failing
--   logical_consistency      0.906   0 failing
--   tool_selection_accuracy  0.814   1 failing (Q7, explained below)
--
-- Both traps were defeated: Q2 scored 1.0, so the fee instruction in the agent stops it
-- reporting total fees as revenue. Q6 scored 1.0 and the agent correctly named SMB.
--
-- WHY Q7 SCORES 0.2 ON TOOL SELECTION AND WHY THAT IS NOT A DEFECT.
-- TSA scores matched tools / max(expected entries, actual calls), so extra calls are
-- penalised. Q7 is an open investigative question and the agent legitimately makes
-- five to ten calls: approval by month, decline reasons, then narrative from search.
-- A fixed expected-tool list cannot match that, and padding the list to game the score
-- would teach the wrong lesson. Q7 is therefore judged on answer_correctness and
-- logical_consistency, where it scores 1.0 on both. The teaching point for session 5 is
-- that TSA suits narrow questions and misreads investigative ones. Q5 scores 0.5 for
-- the same reason: the agent issues two analytics calls where ground truth lists one.

USE ROLE ACCOUNTADMIN;
USE DATABASE FISERV_PAYMENTS_DB;
USE SCHEMA SEMANTIC;

CREATE OR REPLACE TABLE AGENT_EVAL_SET (
    QUESTION_ID     VARCHAR,
    QUESTION        VARCHAR,
    EXPECTED_ANSWER VARCHAR,
    EXPECTED_TOOLS  VARCHAR,    -- comma-separated tool names; tool_selection_accuracy scores against these
    ANSWER_TYPE     VARCHAR,    -- exact_numeric | ranked_list | qualitative | cross_modal
    TRAP            VARCHAR     -- the specific wrong answer this question is designed to catch
);

-- ARRAY_CONSTRUCT is not permitted in a VALUES clause, so tool names are stored as a
-- comma-separated string and split when the evaluation input is assembled.
INSERT INTO AGENT_EVAL_SET VALUES

('Q1',
 'Which month had the lowest card authorisation approval rate, and what was it?',
 'August 2025, at 88.02%. June, July and September all sit at approximately 93.98 to 93.99%, so August is roughly six percentage points below the run rate.',
 'Query_Payments_Analytics',
 'exact_numeric',
 'Reporting a decline rate instead of an approval rate, or missing that the other three months are essentially identical.'),

('Q2',
 'What was our net fee revenue across the whole period?',
 'EUR 1,934,149.64. This excludes interchange and scheme fees, which are passed through to the issuer and the card scheme.',
 'Query_Payments_Analytics',
 'exact_numeric',
 'Answering EUR 3,203,738.89, which is total fees billed to merchants, not revenue retained. That overstates income by about 66%.'),

('Q3',
 'Find merchant feedback mentioning settlement delays where the rating is below 3.',
 'Should return low-rated merchant feedback about delayed or slow settlement and funds arriving late. Roughly 134 records in the corpus match on both criteria. The answer must come from merchant feedback, not support cases, because only feedback carries a rating.',
 'Search_Merchant_Feedback',
 'qualitative',
 'Searching support cases instead of merchant feedback. Support cases have no rating column, so the rating filter would be silently dropped.'),

('Q4',
 'Show processed volume by acquiring region, highest first.',
 'Southern Europe EUR 164.3M, DACH EUR 114.6M, Ireland & France EUR 108.9M, Benelux EUR 73.8M. Total EUR 461.7M.',
 'Query_Payments_Analytics',
 'ranked_list',
 'Including declined and referred authorisations, which would inflate every region.'),

('Q5',
 'What was the most common decline reason in August, and how did it compare with the other months?',
 'Issuer Unavailable, at 38.1% of August declines against 5.0% across the other three months — a roughly sevenfold shift. Do Not Honour also rose, from 20.0% to 29.9%. Insufficient Funds fell from 41.9% to 11.1% as a share, because the issuer-side declines crowded it out.',
 'Query_Payments_Analytics',
 'exact_numeric',
 'Reporting Insufficient Funds because it dominates the full-period totals, without splitting August out.'),

-- Ground truth deliberately scoped to what the question actually asks. An earlier
-- version also demanded merchant counts per segment; the agent answered the volumes
-- correctly and still scored 0.67, because the judge marked the missing counts as an
-- omission. Over-specified ground truth manufactures false failures.
('Q6',
 'Which merchant segment drives the most processed volume?',
 'SMB, at approximately EUR 216.5M. Enterprise is second at approximately EUR 143.3M and Mid-Market third at approximately EUR 102.0M. Naming SMB as the largest and ranking the three segments correctly is sufficient. Noting that Enterprise is more concentrated per merchant is correct but not required.',
 'Query_Payments_Analytics',
 'ranked_list',
 'Answering Enterprise. Enterprise has the highest volume per merchant, but it is not the largest segment by total volume.'),

('Q7',
 'Approval rates dipped in August. What happened, and does the merchant-facing evidence agree?',
 'Approval fell to 88.02% from about 94%. The driver was issuer-side: Issuer Unavailable rose to 38.1% of declines from 5.0%. Support cases and merchant feedback from August independently corroborate this, reporting declined transactions and issuers not responding. The narrative and the numbers agree, and the cause is upstream of Fiserv rather than a terminal or gateway fault.',
 'Query_Payments_Analytics,Search_Support_Cases',
 'cross_modal',
 'Answering only from the semantic view without corroborating from search, or blaming terminals or the gateway when the evidence points at issuers.');

SELECT QUESTION_ID, ANSWER_TYPE, LEFT(QUESTION, 60) AS question FROM AGENT_EVAL_SET ORDER BY QUESTION_ID;
