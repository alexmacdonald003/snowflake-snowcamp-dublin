-- Fiserv Snowcamp 101: semi-structured data for the VARIANT module (session 2).
--
-- Terminal telemetry: what a payment terminal reports back about itself. Genuinely nested,
-- with a device object and an events array, so FLATTEN is required rather than decorative.
-- A flat JSON file would let attendees "learn" VARIANT without ever needing FLATTEN, which is
-- the part they will actually hit in production.
--
-- TWO STAGES ON PURPOSE.
--   TERMINAL_STAGE (internal) holds JSON generated here. The exercise runs against this,
--   so it cannot break if someone else's bucket changes.
--   PUBLIC_DATA_STAGE (external, s3://sfquickstarts/) exists to show what an external stage
--   IS: a pointer at storage Snowflake does not own. Attendees LIST it, they do not depend
--   on its contents.

USE ROLE ACCOUNTADMIN;
USE DATABASE FISERV_101_DB;
USE SCHEMA RAW;
USE WAREHOUSE FISERV_101_WH;

CREATE OR REPLACE FILE FORMAT JSON_FF TYPE = JSON COMPRESSION = NONE;

CREATE OR REPLACE STAGE TERMINAL_STAGE
  FILE_FORMAT = JSON_FF
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'Internal stage holding terminal telemetry JSON for the session 2 VARIANT module.';

-- External stage pointing at a public bucket Snowflake maintains. No credentials needed,
-- which is the point: attendees see a stage reach outside the account without a secret.
CREATE OR REPLACE STAGE PUBLIC_DATA_STAGE
  URL = 's3://sfquickstarts/'
  COMMENT = 'External stage over a public S3 bucket. Read-only, used to show what an external stage is. Do not build an exercise on its contents.';

-- Build the telemetry as VARIANT, then unload it as real JSON files so attendees have to read
-- them off a stage rather than being handed a table.
CREATE OR REPLACE TEMPORARY TABLE TERMINAL_EVENTS_SRC AS
WITH gen AS (
    SELECT SEQ4() + 1 AS n,
           UNIFORM(1, 5000, RANDOM(31))   AS merchant_id,
           UNIFORM(0, 999999, RANDOM(32)) AS r1,
           UNIFORM(0, 999999, RANDOM(33)) AS r2,
           UNIFORM(0, 121, RANDOM(34))    AS r_day
    FROM TABLE(GENERATOR(ROWCOUNT => 3000))
)
SELECT OBJECT_CONSTRUCT(
    'terminal_id',  'TRM' || LPAD((1000 + (n % 1200))::VARCHAR, 6, '0'),
    'merchant_id',  merchant_id,
    'reported_at',  DATEADD(day, r_day, '2025-06-01'::DATE)::VARCHAR,
    'device', OBJECT_CONSTRUCT(
        'model',            GET(ARRAY_CONSTRUCT('Clover Flex','Clover Mini','Clover Station Duo'), r1 % 3)::VARCHAR,
        'firmware_version', GET(ARRAY_CONSTRUCT('4.2.1','4.3.0','4.3.1','5.0.0'), r2 % 4)::VARCHAR,
        'connectivity',     GET(ARRAY_CONSTRUCT('wifi','ethernet','cellular'), r1 % 3)::VARCHAR,
        'battery_percent',  CASE WHEN r1 % 3 = 2 THEN NULL ELSE 20 + (r2 % 80) END
    ),
    'events', ARRAY_CONSTRUCT(
        OBJECT_CONSTRUCT('type', 'heartbeat',
                         'severity', 'info',
                         'latency_ms', 30 + (r1 % 400)),
        OBJECT_CONSTRUCT('type', GET(ARRAY_CONSTRUCT('card_read_failed','reboot','signature_timeout',
                                                     'printer_jam','network_drop'), r2 % 5)::VARCHAR,
                         'severity', GET(ARRAY_CONSTRUCT('warning','error','warning'), r1 % 3)::VARCHAR,
                         'latency_ms', 100 + (r2 % 2000))
    )
) AS payload
FROM gen;

-- Unload as JSON so attendees have to read it off a stage rather than being handed a table.
-- This produces a SINGLE file of about 900KB. MAX_FILE_SIZE was tried at both 200000 and
-- 50000 and Snowflake produced one file either way, because the unload runs single-threaded on
-- an XSMALL and the result set is small. Not worth forcing: reading one JSON file off a stage
-- teaches the stage, VARIANT and FLATTEN just as well as reading six.
COPY INTO @TERMINAL_STAGE/terminal_events
  FROM (SELECT payload FROM TERMINAL_EVENTS_SRC)
  FILE_FORMAT = (TYPE = JSON COMPRESSION = NONE)
  OVERWRITE = TRUE;

ALTER STAGE TERMINAL_STAGE REFRESH;

-- Confirm the files landed and that FLATTEN can reach into them, which is what session 2 asks
-- attendees to work out for themselves.
SELECT 'files on stage' AS check_name, COUNT(*)::VARCHAR AS result
FROM DIRECTORY(@TERMINAL_STAGE)
UNION ALL
SELECT 'events reachable via FLATTEN',
       COUNT(*)::VARCHAR
FROM @TERMINAL_STAGE (FILE_FORMAT => JSON_FF) t,
     LATERAL FLATTEN(input => t.$1:events);
