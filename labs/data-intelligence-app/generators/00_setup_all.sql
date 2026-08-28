-- Fiserv Snowcamp Workshop: day-one provisioning.
--
-- ONE STATEMENT for the attendee. Paste this into a Snowsight worksheet and run it:
--
--     EXECUTE IMMEDIATE FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/data-intelligence-app/generators/00_setup_all.sql;
--
-- Everything then runs SERVER-SIDE. No client, no CLI, no local install. Attendees kick this
-- off at the start of day one and it finishes while Alex presents the 101 slides.
--
-- Measured build times on this account: merchants 17s, authorisations 15s, fee lines 14s,
-- dynamic tables 128s, cortex search 52s, interactive tables 34s. Roughly six minutes.
-- 01_environment.sql creates FISERV_BUILD_WH (LARGE) for the build and the last step here
-- drops it, so the workshop itself runs on XSMALL.
--
-- Text corpora are LOADED from CSV, not regenerated. See 06_load_text_csv.sql for why.
--
-- The agent evaluation (13, 14) is deliberately NOT run here. Building the evaluation set and
-- running it IS the session-5 exercise; pre-running it would hand attendees the answer.
--
-- WHY THIS FILE IS A FLAT LIST AND NOT A LOOP
-- EXECUTE IMMEDIATE FROM cannot appear inside a Snowflake Scripting block: a
-- DECLARE/BEGIN wrapper fails with "syntax error ... unexpected 'EXECUTE'". It also takes a
-- literal path, so the stage cannot be parameterised into a variable. Hence literal paths,
-- repeated. If the stage name changes, search and replace in this file.

EXECUTE IMMEDIATE FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/data-intelligence-app/generators/01_environment.sql;
EXECUTE IMMEDIATE FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/data-intelligence-app/generators/02_merchants.sql;
EXECUTE IMMEDIATE FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/data-intelligence-app/generators/03_authorisations.sql;
EXECUTE IMMEDIATE FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/data-intelligence-app/generators/04_fee_lines.sql;
EXECUTE IMMEDIATE FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/data-intelligence-app/generators/05_payment_products.sql;
EXECUTE IMMEDIATE FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/data-intelligence-app/generators/06_load_text_csv.sql;
EXECUTE IMMEDIATE FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/data-intelligence-app/generators/07_dynamic_tables.sql;
EXECUTE IMMEDIATE FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/data-intelligence-app/generators/08_cortex_search.sql;
EXECUTE IMMEDIATE FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/data-intelligence-app/generators/09_semantic_view.sql;
EXECUTE IMMEDIATE FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/data-intelligence-app/generators/09b_verified_queries.sql;
EXECUTE IMMEDIATE FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/data-intelligence-app/generators/10_interactive_tables.sql;
EXECUTE IMMEDIATE FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/data-intelligence-app/generators/11_governance_dmf_rap.sql;

-- 12_agent.sql is NOT run here. Creating the agent is the first session-5 activity, and
-- pre-building it would hand attendees the exercise. The file stays in the repo as
-- provenance for what a correct agent looks like, not as a step and not as a fallback.

-- Drop the text-generation scaffolding. These four tables exist only because the feedback
-- and support-case corpora were generated before being exported to CSV; they are not data.
-- Leaving them means the very first session-4 prompt, "what tables are in my database",
-- lists GEN_RAW and GEN_REQUESTS, and the first thing an attendee asks is what those are.
DROP TABLE IF EXISTS FISERV_PAYMENTS_DB.RAW.GEN_ANGLES;
DROP TABLE IF EXISTS FISERV_PAYMENTS_DB.RAW.GEN_ITEMS;
DROP TABLE IF EXISTS FISERV_PAYMENTS_DB.RAW.GEN_RAW;
DROP TABLE IF EXISTS FISERV_PAYMENTS_DB.RAW.GEN_REQUESTS;

-- The build warehouse has done its job. SUSPEND rather than DROP: a suspended warehouse
-- costs nothing, and every generator script starts with USE WAREHOUSE FISERV_BUILD_WH, so
-- dropping it means a facilitator cannot re-run any single step to recover from a problem
-- without recreating the warehouse first. Recoverability is worth more than tidiness here.
ALTER WAREHOUSE IF EXISTS FISERV_BUILD_WH SUSPEND;

SELECT 'Setup complete. Now run 99_verify_setup.sql. Every row must say PASS.' AS next_step;
