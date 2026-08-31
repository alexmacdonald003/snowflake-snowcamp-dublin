-- Snowflake SnowCamp Dublin: connect this repo to your Snowflake account.
--
-- Paste this whole file into a Snowsight worksheet and run it. It is the only thing you
-- need to copy by hand all workshop; everything after this comes from the repo itself.
--
-- WHAT IT DOES
-- Creates two objects that let Snowflake read this public GitHub repo directly, then
-- fetches it. Because the repo is public there is no secret, no token and no password:
-- Snowflake reads it anonymously over HTTPS.
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
-- Create the notebooks
-- ---------------------------------------------------------------------------------------
-- Without this you would have to add each notebook by hand in Projects, Notebooks, Create
-- from repository, five times over, choosing a database, schema and warehouse each time.
--
-- A warehouse has to exist before a notebook can reference one, and the lab warehouses do
-- not exist yet: they are created by the provisioning scripts you run next. So make a small
-- one here purely to run notebooks on.
CREATE WAREHOUSE IF NOT EXISTS SNOWCAMP_NB_WH
  WAREHOUSE_SIZE = XSMALL
  AUTO_SUSPEND = 120
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Runs the workshop notebooks. Labs use their own warehouses.';

CREATE SCHEMA IF NOT EXISTS FISERV_SETUP.NOTEBOOKS;

-- Names are prefixed S1 to S5 to match the session numbers on the agenda, so the Notebooks
-- list sorts into the order you will actually work through them.
--
-- Day one, sessions 1 to 3.
CREATE OR REPLACE NOTEBOOK FISERV_SETUP.NOTEBOOKS.S1_SNOWFLAKE_101_PART1
  FROM '@FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/101/notebooks/'
  MAIN_FILE = '101_part1.ipynb'
  QUERY_WAREHOUSE = SNOWCAMP_NB_WH;

CREATE OR REPLACE NOTEBOOK FISERV_SETUP.NOTEBOOKS.S2_SNOWFLAKE_101_PART2
  FROM '@FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/101/notebooks/'
  MAIN_FILE = '101_part2.ipynb'
  QUERY_WAREHOUSE = SNOWCAMP_NB_WH;

CREATE OR REPLACE NOTEBOOK FISERV_SETUP.NOTEBOOKS.S3_SNOWFLAKE_101_PART3
  FROM '@FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/101/notebooks/'
  MAIN_FILE = '101_part3.ipynb'
  QUERY_WAREHOUSE = SNOWCAMP_NB_WH;

-- Day two as notebooks. The web guide is the primary way to follow day two; these are here
-- for anyone who would rather stay inside Snowsight.
CREATE OR REPLACE NOTEBOOK FISERV_SETUP.NOTEBOOKS.S4_ANALYTICS_ETL
  FROM '@FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/data-intelligence-app/notebooks/'
  MAIN_FILE = 'day2_session4.ipynb'
  QUERY_WAREHOUSE = SNOWCAMP_NB_WH;

CREATE OR REPLACE NOTEBOOK FISERV_SETUP.NOTEBOOKS.S5_AGENTS
  FROM '@FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/data-intelligence-app/notebooks/'
  MAIN_FILE = 'day2_session5.ipynb'
  QUERY_WAREHOUSE = SNOWCAMP_NB_WH;

-- A notebook needs a live version before it can be run.
ALTER NOTEBOOK FISERV_SETUP.NOTEBOOKS.S1_SNOWFLAKE_101_PART1 ADD LIVE VERSION FROM LAST;
ALTER NOTEBOOK FISERV_SETUP.NOTEBOOKS.S2_SNOWFLAKE_101_PART2 ADD LIVE VERSION FROM LAST;
ALTER NOTEBOOK FISERV_SETUP.NOTEBOOKS.S3_SNOWFLAKE_101_PART3 ADD LIVE VERSION FROM LAST;
ALTER NOTEBOOK FISERV_SETUP.NOTEBOOKS.S4_ANALYTICS_ETL ADD LIVE VERSION FROM LAST;
ALTER NOTEBOOK FISERV_SETUP.NOTEBOOKS.S5_AGENTS ADD LIVE VERSION FROM LAST;

-- Five notebooks, all in FISERV_SETUP.NOTEBOOKS.
SHOW NOTEBOOKS IN SCHEMA FISERV_SETUP.NOTEBOOKS;

-- ---------------------------------------------------------------------------------------
-- What to do next
-- ---------------------------------------------------------------------------------------
-- Go to Projects, then Notebooks, and open S1_SNOWFLAKE_101_PART1. Its section 0 builds your
-- environment: run those cells and carry on from there. Everything else follows from the
-- notebook, so this worksheet is finished.
--
-- If the Notebooks list looks empty, check the role selector in the top right is set to
-- ACCOUNTADMIN. These notebooks are owned by ACCOUNTADMIN, so another role will not see them.
--
-- If the LS above returned nothing, or any statement errored, tell your facilitator before
-- going further.
--
-- The day two lab guide is a web page rather than a notebook. Open it in a browser tab and
-- keep it beside Snowsight:
--
--     https://alexmacdonald003.github.io/snowflake-snowcamp-dublin/labs/data-intelligence-app/guide/fiserv_workshop_day2.html
