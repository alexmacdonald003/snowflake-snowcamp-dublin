-- Snowflake SnowCamp Dublin: connect this repo to your Snowflake account.
--
-- In Snowsight go to Projects, then Workspaces, then + and SQL File. Paste this whole file
-- in and run it. It is the only thing you copy by hand all workshop; everything after this
-- comes from the repo itself.
--
-- If you are looking for Worksheets, they were removed from Snowsight in June 2026.
-- Workspaces is the SQL editor now.
--
-- WHAT IT DOES
-- Wires your account up to this public GitHub repo, copies the lab files into a Workspace,
-- then builds both days' data. Because the repo is public there is no secret, no token and
-- no password: Snowflake reads it anonymously over HTTPS.
--
-- IT TAKES ABOUT SEVEN MINUTES, almost all of it building tomorrow's data. Start it as soon
-- as you sit down and leave it running; it finishes while the opening slides are on. You do
-- not need to watch it.
--
-- You need ACCOUNTADMIN, which you have on your workshop account.

USE ROLE ACCOUNTADMIN;

-- Holds the git repository object. Also used by the workshop's own setup scripts.
CREATE DATABASE IF NOT EXISTS FISERV_SETUP;

-- Tells Snowflake it may reach GitHub. API_ALLOWED_PREFIXES is a whitelist: nothing
-- outside it is reachable through this integration.
CREATE OR REPLACE API INTEGRATION snowcamp_git_api
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/alexmacdonald003')
  ENABLED = TRUE;

-- The repository clone. No GIT_CREDENTIALS: the repo is public.
CREATE OR REPLACE GIT REPOSITORY FISERV_SETUP.PUBLIC.WORKSHOP
  API_INTEGRATION = snowcamp_git_api
  ORIGIN = 'https://github.com/alexmacdonald003/snowflake-snowcamp-dublin.git';

-- Pull the files. Re-run this line any time to pick up corrections made during the day.
ALTER GIT REPOSITORY FISERV_SETUP.PUBLIC.WORKSHOP FETCH;

-- Prove it worked. You should see the lab directories listed.
LS @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/;
-- ---------------------------------------------------------------------------------------
-- Put the lab files in a Workspace
-- ---------------------------------------------------------------------------------------
-- This copies the whole repo into a Workspace of your own, so the notebooks appear under
-- Projects, Workspaces with nothing further to set up. USER$ is your personal database,
-- which Snowflake creates for you the first time you open Workspaces.
CREATE OR REPLACE WORKSPACE USER$.PUBLIC.SNOWCAMP_DUBLIN
  FROM '@FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/';

-- A live version is what makes the files editable.
ALTER WORKSPACE USER$.PUBLIC.SNOWCAMP_DUBLIN ADD LIVE VERSION FROM LAST;

-- You should see the three day-one notebooks among the files.
LIST 'snow://workspace/USER$.PUBLIC.SNOWCAMP_DUBLIN/versions/head/labs/101/notebooks/';

-- ---------------------------------------------------------------------------------------
-- Build the data
-- ---------------------------------------------------------------------------------------
-- Everything from here runs server-side: no client, no CLI, no local install.
-- EXECUTE IMMEDIATE FROM reads the SQL straight off the repo and runs it in your account.
--
-- ORDER MATTERS. Day two is built first even though it is the slow one, because the day one
-- build depends on it: 03_text_and_governance.sql builds the 101 feedback table by selecting
-- from FISERV_PAYMENTS_DB.RAW.MERCHANT_FEEDBACK, reusing the day-two corpus rather than
-- generating a second one. Run day one first and it fails with "Database 'FISERV_PAYMENTS_DB'
-- does not exist". There is no dependency in the other direction.
--
-- Day two: roughly six minutes for 2,000,000 merchants, 30.2 million fee lines, five dynamic
-- tables, two Cortex Search services and a semantic view. It builds on a LARGE warehouse that
-- suspends itself when it finishes.
--
-- It deliberately does NOT build the Cortex Agent or the evaluation set. Those are the
-- session 5 exercises, and pre-building them would hand you the answers.
EXECUTE IMMEDIATE FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/data-intelligence-app/generators/00_setup_all.sql;

-- Day one: quick by comparison. 5,000 merchants and 500,000 transactions, seconds rather
-- than minutes. Ends by running its own 7-check verification.
EXECUTE IMMEDIATE FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/101/generators/00_setup_all_101.sql;

-- ---------------------------------------------------------------------------------------
-- Keep notebook sessions short
-- ---------------------------------------------------------------------------------------
-- Notebooks run on a Snowflake-managed notebook service, and each service holds a compute
-- pool node while it is running. The default idle timeout offered is 24 hours, which would
-- leave it running overnight between day one and day two. This makes 15 minutes the
-- pre-selected choice instead.
ALTER ACCOUNT SET NOTEBOOK_VNEXT_IDLE_TIMEOUT_OPTIONS_MINUTES = '15,30,60';

-- The notebooks need a compute pool. Confirm one is available before you go further.
SHOW COMPUTE POOLS LIKE 'SYSTEM_COMPUTE_POOL_CPU';

-- ---------------------------------------------------------------------------------------
-- Check it worked
-- ---------------------------------------------------------------------------------------
-- This is the last statement, so its result is the one left on screen.
--
-- Expect 7 rows and every STATUS to say PASS. FAIL rows sort to the top, so if the first
-- row says PASS you are ready. If anything says FAIL, tell your facilitator the CHECK_NAME
-- rather than trying to fix it. Do not start the lab on a broken account.
--
-- This checks day one only. Day two has its own 20-check verification, and the day two lab
-- guide runs it as its first step.
EXECUTE IMMEDIATE FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/101/generators/99_verify_101.sql;

-- ---------------------------------------------------------------------------------------
-- WHAT TO DO NEXT
-- ---------------------------------------------------------------------------------------
-- Everything is in place. In the left nav choose Projects, then Workspaces, and open the
-- SNOWCAMP_DUBLIN workspace. Then open:
--
--     labs/101/notebooks/101_part1.ipynb
--
-- It will ask you to connect to a notebook service. Accept the defaults, including the
-- 15 minute idle timeout, which the statement above has already made the pre-selected
-- option. Give it a minute or two to start. The notebook re-runs the
-- same 7 checks as its first cell, then goes straight into the first exercise.
--
-- PICKING UP CORRECTIONS DURING THE DAY
-- If a facilitator fixes something in the repo, run these two lines again. The second one
-- discards any edits you have made to the lab files, which is usually what you want:
--
--     ALTER GIT REPOSITORY FISERV_SETUP.PUBLIC.WORKSHOP FETCH;
--     CREATE OR REPLACE WORKSPACE USER$.PUBLIC.SNOWCAMP_DUBLIN
--       FROM '@FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/';
--     ALTER WORKSPACE USER$.PUBLIC.SNOWCAMP_DUBLIN ADD LIVE VERSION FROM LAST;
--
-- Note this workspace is a copy of the repo, not a live Git connection, so there is no
-- Pull button and no pushing back. Re-running the three lines above is the way to refresh.
--
-- TROUBLESHOOTING
-- If any statement above failed, check the role selector in the top right is ACCOUNTADMIN,
-- then tell your facilitator before going further.
--
-- If you would rather connect a real Git-synced workspace, you can: Projects, Workspaces,
-- From Git repository, paste the URL below, choose SNOWCAMP_GIT_API as the API integration
-- and pick the "Public repository" option so no credentials are needed.
--
--     https://github.com/alexmacdonald003/snowflake-snowcamp-dublin
--
-- DAY TWO is a web page rather than a notebook. Open it in a browser tab and keep it beside
-- Snowsight:
--
--     https://alexmacdonald003.github.io/snowflake-snowcamp-dublin/labs/data-intelligence-app/guide/fiserv_workshop_day2.html
