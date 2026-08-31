-- Fiserv Snowcamp Workshop: day-one 101 provisioning.
--
-- ONE STATEMENT for the attendee. Paste this into a Snowsight SQL file (Projects,
-- Workspaces, +, SQL File) and run it:
--
--     EXECUTE IMMEDIATE FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/101/generators/00_setup_all_101.sql;
--
-- Everything runs SERVER-SIDE. No client, no CLI, no local install.
--
-- This builds FISERV_101_DB only, for day-one sessions 1 to 3. It is quick: seconds, not
-- minutes, because the 101 data is small on purpose (5,000 merchants, 500,000 transactions).
--
-- The day-two payments environment is a SEPARATE, much larger build that takes about six
-- minutes. Kick that off at the start of day one too, so it finishes while the 101 slides
-- are running:
--
--     EXECUTE IMMEDIATE FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/data-intelligence-app/generators/00_setup_all.sql;
--
-- WHY THIS FILE IS A FLAT LIST AND NOT A LOOP
-- EXECUTE IMMEDIATE FROM cannot appear inside a Snowflake Scripting block: a DECLARE/BEGIN
-- wrapper fails with "syntax error ... unexpected 'EXECUTE'". It also takes a literal path,
-- so the stage cannot be parameterised into a variable. Hence literal paths, repeated.
-- If the stage name changes, search and replace in this file.

EXECUTE IMMEDIATE FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/101/generators/01_environment_and_seed.sql;
EXECUTE IMMEDIATE FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/101/generators/02_json_stage.sql;
EXECUTE IMMEDIATE FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/101/generators/03_text_and_governance.sql;

-- Prove it worked. Every row must say PASS.
EXECUTE IMMEDIATE FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/101/generators/99_verify_101.sql;
