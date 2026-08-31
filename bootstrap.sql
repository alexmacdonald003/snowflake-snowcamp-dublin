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
-- Creates the two objects that let Snowflake read this public GitHub repo directly, then
-- fetches it. You will point a Workspace at the same repo in a moment; the objects here are
-- what the setup scripts run from. Because the repo is public there is no secret, no token and no password:
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
-- WHAT TO DO NEXT: connect a Workspace to the repo
-- ---------------------------------------------------------------------------------------
-- The lab notebooks live in the repo you just fetched. To open and run them you need a
-- Workspace connected to that repo. This part is done in the UI; there is no SQL for it.
--
--   1. In the left nav choose Projects, then Workspaces.
--   2. In the Workspaces menu choose From Git repository.
--   3. Repository URL:
--
--          https://github.com/alexmacdonald003/snowflake-snowcamp-dublin
--
--   4. API integration: choose SNOWCAMP_GIT_API, created above.
--   5. Authentication: choose Public repository. There is no username, token or password
--      to enter. You will not be able to push changes back, which is intended.
--   6. Choose Create.
--
-- You now have the whole repo as a file tree. Open:
--
--     labs/101/notebooks/101_part1.ipynb
--
-- It will ask you to connect to a notebook service. Accept the defaults, set the idle
-- timeout to 15 minutes, and give it a minute or two to start. Then run section 0, which
-- builds your databases, warehouses and data, and finishes with 11 checks that should all
-- say PASS.
--
-- TROUBLESHOOTING
-- Empty file tree, or the repo will not connect: check the role selector in the top right
-- is ACCOUNTADMIN. The API integration above is owned by ACCOUNTADMIN and another role
-- cannot see it.
--
-- If the LS above returned nothing, or any statement errored, tell your facilitator before
-- going further.
--
-- DAY TWO is a web page rather than a notebook. Open it in a browser tab and keep it beside
-- Snowsight:
--
--     https://alexmacdonald003.github.io/snowflake-snowcamp-dublin/labs/data-intelligence-app/guide/fiserv_workshop_day2.html
