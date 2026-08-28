-- Fiserv Snowcamp Workshop: environment for the payments data intelligence lab.
-- Creates the database, schemas and warehouses the lab builds on.
-- Runs as ACCOUNTADMIN. Idempotent.

USE ROLE ACCOUNTADMIN;

-- Database and schemas. RAW holds source tables; the rest mirror the lab's layers.
CREATE DATABASE IF NOT EXISTS FISERV_PAYMENTS_DB;
USE DATABASE FISERV_PAYMENTS_DB;

CREATE SCHEMA IF NOT EXISTS RAW;              -- source tables
CREATE SCHEMA IF NOT EXISTS DYNAMIC_TABLES;   -- 3-tier declarative pipeline
CREATE SCHEMA IF NOT EXISTS INTERACTIVE;      -- low-latency serving tables
CREATE SCHEMA IF NOT EXISTS SEMANTIC;         -- semantic view, agent, eval data
CREATE SCHEMA IF NOT EXISTS DBT_STAGING;      -- dbt staging models
CREATE SCHEMA IF NOT EXISTS DBT_ANALYTICS;    -- dbt mart models

-- Standard warehouse. Deliberately left small: the Interactive Tables comparison
-- in session 4 depends on the standard path being genuinely slower under load.
CREATE WAREHOUSE IF NOT EXISTS FISERV_WH
  WAREHOUSE_SIZE = XSMALL
  AUTO_SUSPEND = 120
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Standard warehouse for the Fiserv payments lab';

-- Gen2 warehouse for the Optima indexing module.
-- Syntax note: Gen2 is set with GENERATION = '2' as a string.
CREATE WAREHOUSE IF NOT EXISTS FISERV_GEN2_WH
  WAREHOUSE_SIZE = XSMALL
  GENERATION = '2'
  AUTO_SUSPEND = 120
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Gen2 warehouse: demonstrates Optima indexing and partition pruning';

-- Interactive warehouse for low-latency point lookups.
-- Note: interactive warehouses require AUTO_SUSPEND of at least 86400 seconds.
CREATE WAREHOUSE IF NOT EXISTS FISERV_INTERACTIVE_WH
  WAREHOUSE_TYPE = 'INTERACTIVE'
  WAREHOUSE_SIZE = XSMALL
  AUTO_SUSPEND = 86400
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Interactive warehouse: sub-second point lookups under concurrency';

-- Build warehouse: temporarily larger for the bulk generation phase only.
-- Sizing up is roughly cost-neutral on scan-bound bulk work and cuts wall clock.
-- 99_reset.sql drops this so it cannot be mistaken for a lab warehouse.
CREATE WAREHOUSE IF NOT EXISTS FISERV_BUILD_WH
  WAREHOUSE_SIZE = LARGE
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Temporary build warehouse for bulk data generation. Dropped after setup.';

SELECT 'Environment created' AS status;
