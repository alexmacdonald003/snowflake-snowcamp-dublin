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
  API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-amacdonald')
  ENABLED = TRUE;

-- The repository clone. No GIT_CREDENTIALS: the repo is public.
CREATE OR REPLACE GIT REPOSITORY FISERV_SETUP.PUBLIC.WORKSHOP
  API_INTEGRATION = snowcamp_git_api
  ORIGIN = 'https://github.com/sfc-gh-amacdonald/snowflake-snowcamp-dublin.git';

-- Pull the files. Re-run this line any time to pick up corrections made during the day.
ALTER GIT REPOSITORY FISERV_SETUP.PUBLIC.WORKSHOP FETCH;

-- Prove it worked. You should see the lab directories listed.
LS @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/;

-- If that returned rows, you are ready. Day one starts here:
--
--     EXECUTE IMMEDIATE FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/101/generators/00_setup_all_101.sql;
--
-- If it returned nothing, or errored, tell your facilitator before going further.
