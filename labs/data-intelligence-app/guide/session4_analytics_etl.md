# Session 4 — Analytics and ETL with CoCo

**Building an End-to-End Application Using CoCo on Snowflake**
*Fiserv Snowcamp, Dublin, 3 September 2026*

## Overview

In this hands-on lab you will build a complete AI-powered payments analytics platform
entirely within Snowflake, with no external infrastructure and nothing installed on your
laptop. Using Snowflake CoCo in Snowsight as your AI-assisted development environment,
you will work through the full data lifecycle: explore acquiring data you have never seen
before, monitor its quality with Data Metric Functions, transform it through a three-tier
Dynamic Tables pipeline, build tested analytical models with dbt, compare Gen2 warehouses
against standard ones, and serve sub-second point lookups with Interactive Tables.

Session 5 puts a Cortex Agent on top of what you build here and asks the harder question:
how do you know the answers are right?

### What You'll Learn

- Accelerate development with Snowflake CoCo in Snowsight (AI-assisted SQL, deployment, and data exploration)
- Explore an unfamiliar schema and reach a defensible number without being told the grain
- Monitor data quality automatically with Data Metric Functions, and find what they miss
- Transform data with a three-tier Dynamic Tables pipeline and verify the refresh mode you actually got
- Build analytical models with dbt, and diagnose failing tests rather than silencing them
- Compare Gen2 warehouses against standard warehouses honestly
- Serve low-latency queries at high concurrency with Interactive Tables
- Create a custom CoCo skill so a one-off check becomes something the next person inherits

### What You'll Build

A production-grade payments analytics platform on Snowflake: a monitored, tested,
incrementally refreshing pipeline over 30 million fee lines, served for low-latency
lookups, with a reusable data quality skill. Everything you build here is what session 5's
agent will answer questions from.

### Prerequisites

- A browser and your Snowflake account details. Nothing to install.
- Basic familiarity with SQL. You will read more of it than you write.

### The Data

Fiserv acquiring data for June to September 2025, in euro. Two million merchants, ten
million authorisations, 30 million fee lines, plus merchant feedback and support cases as
free text.

| Object | Grain | Matters because |
|---|---|---|
| `RAW.AUTHORISATIONS` | one row per authorisation attempt | attempts are not volume |
| `RAW.FEE_LINES` | **three rows per authorisation** | joining it to authorisations inflates any sum |
| `RAW.MERCHANTS` | one row per merchant | carries the row access policy used in session 5 |
| `RAW.MERCHANT_FEEDBACK` | one row per comment | free text, searched not queried |
| `RAW.SUPPORT_CASES` | one row per case | free text |

### Table of Contents

1. Setup
2. Explore Your Data
3. Data Quality
4. Dynamic Tables Pipeline
5. dbt Analytics
6. Gen2 Warehouse: Optima Indexing
7. Interactive Tables
8. CoCo Custom Skill

## Setup

Your account was provisioned on day one by the setup script, while the 101 slides were
running, so there is nothing to install and nothing to clone. This step confirms it worked.

Open **Projects → Workspaces** in Snowsight and open your `SNOWCAMP_DUBLIN` workspace.
Confirm `labs/data-intelligence-app/AGENTS.md` is present. CoCo reads it automatically, so it
already knows the payments schemas and the four definitions that are easy to get wrong.

First pin your context. Every cell below depends on this, and the unqualified
`INFORMATION_SCHEMA` calls later on resolve against whatever database is current.

```sql
-- Pins role, database, schema and warehouse for every cell below. Re-run this if a
-- later cell cannot find an object.
USE ROLE ACCOUNTADMIN;
USE DATABASE FISERV_PAYMENTS_DB;
USE SCHEMA RAW;
USE WAREHOUSE FISERV_WH;
```

### Verify Your Account

Your account was provisioned on day one. **Run this before anything else.** It is
the difference between finding a problem now and finding it at 09:30 with the room ahead of
you.

**Prompt CoCo:**

> Run this and show me any row that does not say PASS: EXECUTE IMMEDIATE FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/data-intelligence-app/generators/99_verify_setup.sql

Or run it yourself:

```sql
-- Every row must say PASS. Run this first, every session.
EXECUTE IMMEDIATE FROM
  @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/data-intelligence-app/generators/99_verify_setup.sql;
```

Expect **20 rows, all PASS**. The checks cover row counts on the four RAW tables, the five
dynamic tables, both Cortex Search services, the semantic view, the interactive tables, and
the governance policies.

If any row says FAIL, tell your facilitator the row name before you try to fix it. Do not
start the lab on a broken account.

### If Verification Fails

Everything in this workshop is built by one server-side script. There is no client, no CLI
and no local install: `EXECUTE IMMEDIATE FROM` reads the SQL straight off an internal stage
and runs it in your account.

```sql
-- Rebuilds the whole payments environment from scratch. Roughly six minutes.
-- ONLY run this if verification failed. It drops and recreates the databases, so
-- anything you have already built in this session is lost.
EXECUTE IMMEDIATE FROM
  @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/data-intelligence-app/generators/00_setup_all.sql;
```

That orchestrator runs eleven steps in order: `01_environment.sql` creates the database,
schemas and warehouses; `02` to `06` build 2,000,000 merchants, the authorisations, 30.2
million fee lines and the text corpora; `07` to `11` build the dynamic tables, Cortex Search
services, semantic view, interactive tables and the governance policies.

Two things it deliberately does **not** build: the Cortex Agent and the evaluation set. Those
are the session 5 exercises, and pre-building them would hand you the answers.

Re-run the verification from **Verify Your Account** above and confirm all 20 rows say PASS
before continuing. If any row still fails, tell your facilitator now rather than debugging into
the session.

**If a prompt goes wrong at any point**, do not reach for a script. You have two moves.

When you cannot judge whether the answer is right, ask CoCo to show its working:

> Show me the SQL you just ran and explain why you chose those tables and that grain. I want to check it before I trust the number.

When you know it is wrong, say so plainly:

> That is not what I expected. I wanted X but I got Y. Explain what went wrong and fix it.

CoCo has `AGENTS.md` and the full schema. Recovery is a conversation, not a fallback file.

## Explore Your Data

Before transforming anything, build a mental model of the dataset. Four questions get you
there, and you can ask all of them without knowing the schema.

**Prompt CoCo:**

> What schemas and tables are in my database?

CoCo queries `INFORMATION_SCHEMA` and shows the structure: `RAW` (source tables), `DBT_STAGING`
(staging views), `DBT_ANALYTICS` (dbt models), `DYNAMIC_TABLES` (the pipeline), `INTERACTIVE`
(low-latency lookups) and `SEMANTIC` (the AI layer).

```sql
-- The shape of the database, one row per table.
SELECT TABLE_SCHEMA, TABLE_NAME, TABLE_TYPE, ROW_COUNT
FROM FISERV_PAYMENTS_DB.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA <> 'INFORMATION_SCHEMA'
ORDER BY TABLE_SCHEMA, TABLE_NAME;
```

Next, look at actual rows. Averages hide things that individual records do not.

> Show me 5 sample rows from the authorisations table

```sql
SELECT * FROM FISERV_PAYMENTS_DB.RAW.AUTHORISATIONS LIMIT 5;
```

Then the scale of it:

> How many authorisations, merchants and payment products do we have?

```sql
-- Row counts across the source tables.
SELECT 'AUTHORISATIONS' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM FISERV_PAYMENTS_DB.RAW.AUTHORISATIONS
UNION ALL SELECT 'FEE_LINES',         COUNT(*) FROM FISERV_PAYMENTS_DB.RAW.FEE_LINES
UNION ALL SELECT 'MERCHANTS',         COUNT(*) FROM FISERV_PAYMENTS_DB.RAW.MERCHANTS
UNION ALL SELECT 'PAYMENT_PRODUCTS',  COUNT(*) FROM FISERV_PAYMENTS_DB.RAW.PAYMENT_PRODUCTS
UNION ALL SELECT 'MERCHANT_FEEDBACK', COUNT(*) FROM FISERV_PAYMENTS_DB.RAW.MERCHANT_FEEDBACK
UNION ALL SELECT 'SUPPORT_CASES',     COUNT(*) FROM FISERV_PAYMENTS_DB.RAW.SUPPORT_CASES
ORDER BY ROW_COUNT DESC;
```

Expect **10,000,000** authorisations, **30,253,689** fee lines, **2,000,000** merchants,
**10** payment products, **1,200** feedback rows and **1,200** support cases.

Note the ratio between the first two: roughly **three fee lines per authorisation**. Hold on
to that number, because it matters shortly.

Finally, the time window:

> What's the date range of our authorisation data?

```sql
SELECT MIN(AUTH_TIMESTAMP)::DATE AS FIRST_DAY,
       MAX(AUTH_TIMESTAMP)::DATE AS LAST_DAY,
       COUNT(DISTINCT DATE_TRUNC('month', AUTH_TIMESTAMP)) AS MONTHS
FROM FISERV_PAYMENTS_DB.RAW.AUTHORISATIONS;
```

Expect **1 June to 30 September 2025**, four months. The data is historical on purpose, so
every figure in this guide is reproducible.

That is your mental model. Now the headline number.

> What was our total processed volume for the whole period, and how does it split by acquiring region?

```sql
-- The headline figure: approved volume by region. Approved only, because a declined
-- transaction earns nothing.
SELECT m.ACQUIRING_REGION,
       COUNT(*)                     AS APPROVED_AUTHS,
       ROUND(SUM(a.AUTH_AMOUNT), 2) AS PROCESSED_VOLUME_EUR
FROM FISERV_PAYMENTS_DB.RAW.AUTHORISATIONS a
JOIN FISERV_PAYMENTS_DB.RAW.MERCHANTS m
  ON a.MERCHANT_ID = m.MERCHANT_ID
WHERE a.AUTH_RESULT = 'Approved'
GROUP BY m.ACQUIRING_REGION
ORDER BY PROCESSED_VOLUME_EUR DESC;
```

Expect roughly **€461.7M** in total, with Southern Europe largest at about €164.3M. Note
the `AUTH_RESULT = 'Approved'` filter: a declined transaction earns nothing, and including
declines is the most common error in payments reporting.

### The Trap

You now know there are three fee lines per authorisation. Watch what happens if you forget it.
Ask this deliberately badly:

> Join AUTHORISATIONS to FEE_LINES and give me total processed volume by region.

```sql
-- Deliberately wrong. FEE_LINES has three rows per authorisation, so joining it
-- multiplies every AUTH_AMOUNT by three before summing.
SELECT m.ACQUIRING_REGION,
       ROUND(SUM(a.AUTH_AMOUNT), 2) AS INFLATED_VOLUME_EUR
FROM FISERV_PAYMENTS_DB.RAW.AUTHORISATIONS a
JOIN FISERV_PAYMENTS_DB.RAW.FEE_LINES f
  ON a.AUTH_ID = f.AUTH_ID
JOIN FISERV_PAYMENTS_DB.RAW.MERCHANTS m
  ON a.MERCHANT_ID = m.MERCHANT_ID
WHERE a.AUTH_RESULT = 'Approved'
GROUP BY m.ACQUIRING_REGION
ORDER BY INFLATED_VOLUME_EUR DESC;
```

Read the answer carefully. If the total comes back near **€1,565M** rather than €461.7M,
the fan-out has inflated it about 3.4 times. Push back:

> That looks about three times too high. Explain why, and give me the correct figure.

**What to take away:** a plausible number is not a correct number. The fan-out is
invisible unless you know the grain, and nothing errored.

## Data Quality

**Data Metric Functions (DMFs)** let you attach automated quality checks directly to table
columns. Snowflake runs them on a schedule and stores results in
`SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS`. Built-in DMFs include `NULL_COUNT`,
`DUPLICATE_COUNT`, `UNIQUE_COUNT` and `FRESHNESS`, or you can write custom ones.

Think smoke detectors for your data: useful, and only where you fitted them.

**Prompt CoCo:**

> What Data Metric Functions are attached to tables in FISERV_PAYMENTS_DB.RAW, and what are they monitoring?

```sql
-- Which columns on FEE_LINES carry a quality monitor, and on what schedule.
SELECT REF_ENTITY_NAME AS TABLE_NAME,
       METRIC_NAME,
       REF_ARGUMENTS    AS MONITORED_COLUMN,
       SCHEDULE
FROM TABLE(INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(
    REF_ENTITY_NAME => 'FISERV_PAYMENTS_DB.RAW.FEE_LINES',
    REF_ENTITY_DOMAIN => 'TABLE'));
```

Then look at what they are reporting:

> Show me the latest results from those monitors. Are any of them reporting violations?

You will see NULLs reported on `AUTH_AMOUNT` and `FEE_AMOUNT_EUR`, and a clean result on
`FEE_CATEGORY`. At this point the data looks like it has two known issues, both watched.

### Discover the Gap

**Prompt CoCo:**

> Check every column in FEE_LINES for NULLs, not just the monitored ones. Is anything unmonitored also broken?

```sql
-- NULL counts across every column, monitored or not. This is the cell that finds
-- what the monitors missed.
SELECT COUNT(*)                                            AS TOTAL_ROWS,
       COUNT_IF(FEE_TYPE IS NULL)                          AS FEE_TYPE_NULLS,
       COUNT_IF(FEE_CATEGORY IS NULL)                      AS FEE_CATEGORY_NULLS,
       COUNT_IF(FEE_AMOUNT_EUR IS NULL)                    AS FEE_AMOUNT_NULLS
FROM FISERV_PAYMENTS_DB.RAW.FEE_LINES;
```

`FEE_TYPE` has **152 NULLs and no monitor on it**. The monitor was attached to
`FEE_CATEGORY`, the column next to it, which is completely clean. Two monitors, both
reporting comfortably, and the actual problem sitting in the gap between them.

### Fix the Coverage

**Prompt CoCo:**

> Move the monitor to where it should have been, and tell me what the count is once it runs.

```sql
-- Attach the monitor to the column that is actually broken.
ALTER TABLE FISERV_PAYMENTS_DB.RAW.FEE_LINES
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (FEE_TYPE);
```

**What to take away:** a monitor tells you about the column it is attached to and nothing
else. Coverage is a decision, and yours was wrong. This is the most common data quality
failure in production and it never shows up as an error.

## Dynamic Tables Pipeline

**Dynamic Tables** are declarative data pipelines. You define the target state as a SQL query
and Snowflake handles incremental refresh automatically. The `TARGET_LAG` parameter controls
freshness: set a time-based lag such as `'1 minute'`, or use `DOWNSTREAM`.

`DOWNSTREAM` is worth reading carefully, because the name describes the *direction the
schedule comes from*, not what triggers it. A `DOWNSTREAM` table has no schedule of its own;
it refreshes when a table that **depends on it** needs fresh data, taking its timing from the
shortest lag among its consumers. A `DOWNSTREAM` table with no consumers therefore never
refreshes on its own, and Snowflake raises no warning about that.

This pipeline sets an explicit one-minute lag on the tier 1 tables and `DOWNSTREAM` on
everything below, which is why the tier 3 tables hold data from their initial build.

**Prompt CoCo:**

> Explain the Dynamic Table pipeline in FISERV_PAYMENTS_DB.DYNAMIC_TABLES. Draw the dependency graph, and tell me the target lag and refresh mode of each table.

```sql
-- List the pipeline. SHOW exposes the refresh mode, which the DDL does not tell you.
SHOW DYNAMIC TABLES IN SCHEMA FISERV_PAYMENTS_DB.DYNAMIC_TABLES;
```

```sql
-- Read the previous cell's output as a table. REFRESH_MODE_REASON is the column that
-- matters: null means you got what you asked for.
SELECT "name"                AS DYNAMIC_TABLE,
       "target_lag"          AS TARGET_LAG,
       "refresh_mode"        AS REFRESH_MODE,
       "refresh_mode_reason" AS REFRESH_MODE_REASON
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
```

Five tables in three tiers. Tiers 1 and 2 use a one-minute lag; tier 3 uses `DOWNSTREAM`,
which means it refreshes only when something downstream needs it.

### Why Refresh Mode Matters

**Prompt CoCo:**

> Why is every one of these INCREMENTAL rather than FULL, and what would have happened if I had not set the refresh mode explicitly?

This is the point of the step. Left to itself, Snowflake looks at the tier 1 joins, judges
them complex, and **silently sets refresh mode to FULL**. That then cascades: tier 2 fails
to build at all, because change tracking is not supported on a dynamic table that
refreshes FULL. A pipeline that appears to work can be quietly reprocessing everything on
every cycle.

`REFRESH_MODE_REASON` is null when you got what you asked for. It only fills in to explain
a downgrade, so a null there is good news.

### Explore Results

**Prompt CoCo:**

> Add a new tier 3 dynamic table showing chargeback rate by merchant segment and month. Make sure it refreshes incrementally, and prove to me that it does.

A good answer proves it from `DYNAMIC_TABLE_REFRESH_HISTORY` after a refresh, not from the
DDL it just wrote. Anything that only shows you the `CREATE` statement has not proved
anything.

> Insert a handful of new authorisations into RAW.AUTHORISATIONS and show me the change flowing through all three tiers.

**What to take away:** declarative does not mean unexamined. Always check the refresh mode
you actually got, not the one you assumed.

## dbt Analytics

**dbt Projects on Snowflake** makes a dbt project a first-class Snowflake object. You run it
with `EXECUTE DBT PROJECT` and it executes server-side, so there is no local dbt install, no
virtualenv and no profiles.yml to manage. That is what makes it usable from a browser.

Models are SQL files with dependencies expressed as `ref()`, materialising here into
`DBT_ANALYTICS`. Tests live alongside the models and run as part of the build, which means a
failing test is a build signal rather than something you discover in a dashboard later.

**Prompt CoCo:**

> There is a dbt project object in FISERV_PAYMENTS_DB.DBT_STAGING. Explain its structure: what the staging models do, what the analytics models do, and what the tests check.

Then run it:

> Run the whole project and tests.

**It will fail. That is the exercise.** 31 tests pass and 2 fail:
`not_null_fct_fee_economics_net_fee_revenue_eur` (60 rows) and
`not_null_fct_merchant_performance_processed_volume_eur` (42 rows).

### Diagnose Before Fixing

**Prompt CoCo:**

> Two tests failed. Do not fix them yet. Explain exactly why they failed and trace the cause back to the source data.

```sql
-- The chain to find: all-NULL aggregate groups. SUM() of an all-NULL group returns
-- NULL, not 0, so bad source rows become broken aggregate rows further downstream.
SELECT COUNT_IF(FEE_AMOUNT_EUR IS NULL) AS NULL_FEE_AMOUNTS
FROM FISERV_PAYMENTS_DB.RAW.FEE_LINES;
```

```sql
-- The second half of the chain: NULL authorisation amounts.
SELECT COUNT_IF(AUTH_AMOUNT IS NULL) AS NULL_AUTH_AMOUNTS
FROM FISERV_PAYMENTS_DB.RAW.AUTHORISATIONS;
```

215 NULL fee amounts and 189 NULL auth amounts land in aggregate groups where **every**
row is NULL. So 404 bad source rows become 102 broken aggregate rows. **The models are
correct. The data is not.**

### Fix It

**Prompt CoCo:**

> Now fix it. I want the money to still reconcile, and I want the fix to make the missing data visible rather than hiding it. Explain the tradeoff in whatever you choose.

There is more than one defensible answer. Coalescing to zero makes the build pass but
buries the problem. Excluding the rows changes the totals. Splitting out an explicit
"unknown" bucket keeps both the total and the visibility. A good answer states which it
chose and what it gave up; any answer that silently coalesces to zero without saying so
has failed.

> Re-run the project and confirm we are green. Then add a test that would have caught this at the staging layer instead of three models downstream.

**What to take away:** a failing test is information. The instinct to make the red go away
is what turns a data quality problem into a reporting problem.

## Gen2 Warehouse: Optima Indexing

Gen2 warehouses bring **Snowflake Optima**, a set of optimisations that learn from your query
patterns and apply themselves with no configuration, no clustering keys to define and no extra
cost. There are three parts, and they do different jobs:

| Feature | What it does |
|---|---|
| **Optima Indexing** | Spots repetitive point-lookup queries and builds hidden indexes to accelerate them. Built on the search optimization service. |
| **Optima Metadata** | Adds metadata for columns used inefficiently in filters, improving **partition pruning**. |
| **Optima Planning** | Learns better query plans by observing how queries actually execute. |

So indexing accelerates lookups and metadata improves pruning. It is a common slip to credit
pruning to indexing. All three are available on Gen2 standard and Adaptive warehouses, in
every edition.

Because Optima applies itself, the only way to know it fired is to look. Query Profile's
**Statistics** pane has a row labelled *Partitions pruned by Snowflake Optima*, the **Query
insights** pane shows *Snowflake Optima used*, and both are queryable through the
`QUERY_INSIGHTS` view. Measure the difference, then confirm the cause rather than assuming it.

**Prompt CoCo:**

> Compare FISERV_WH and FISERV_GEN2_WH. What is different about them?

```sql
-- Compare the two warehouses. Look at the GENERATION property.
SHOW WAREHOUSES LIKE 'FISERV_%WH';
```

### Compare to Standard Warehouse

**Prompt CoCo:**

> Write me an expensive analytical query over AUTHORISATIONS and FEE_LINES, something with real joins and aggregation rather than a point lookup. Run it on both warehouses and compare execution time, not elapsed time. Run each one twice and use the second run, so I am not measuring warehouse resume.

```sql
-- Turn off the result cache first, or the second run returns instantly and
-- measures nothing at all.
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
```

```sql
-- Server-side timings for both warehouses. Judge on EXECUTION_MS, not on the elapsed
-- time the notebook reports, which includes round trip.
SELECT WAREHOUSE_NAME,
       WAREHOUSE_SIZE,
       EXECUTION_TIME AS EXECUTION_MS,
       COMPILATION_TIME AS COMPILE_MS,
       BYTES_SCANNED
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION())
WHERE WAREHOUSE_NAME IN ('FISERV_WH', 'FISERV_GEN2_WH')
ORDER BY START_TIME DESC
LIMIT 10;
```

Then ask the question that matters:

> Is that difference big enough to justify moving our ETL to Gen2? What would you need to measure over a week to answer that properly?

A good answer refuses to generalise from one query on an idle warehouse.

**What to take away:** one measurement is not a benchmark. Be honest about what a single
number can and cannot tell you.

## Interactive Tables

**Interactive Tables** are purpose-built for low-latency, high-concurrency point lookups. They
keep data laid out for equality predicates, delivering sub-second responses for dashboard
filters and application queries.

Three things to know before you use one:

- **`CLUSTER BY` is required**, not optional. Choose the columns your most time-critical
  `WHERE` clauses filter on, because that choice drives the performance.
- **The table only performs when queried through an interactive warehouse with the table
  attached** via `ALTER WAREHOUSE ... ADD TABLES`. The warehouse pre-warms a local data cache
  for attached tables, and that cache is the actual mechanism. Query one from a standard
  warehouse and it behaves like an ordinary table.
- **DML is not supported** apart from `INSERT OVERWRITE`. A static interactive table never
  refreshes until you replace it; add `TARGET_LAG` to make it a dynamic interactive table that
  refreshes itself.

That cache is also why the first measurement in this section will mislead you.

**Prompt CoCo:**

> Explain the difference between INTERACTIVE.AUTH_LOOKUP and INTERACTIVE.STD_AUTH_LOOKUP. Why does one need a clustering key and the other does not?

### Point Lookups

**Prompt CoCo:**

> Pick one AUTH_ID and query it from both tables. Compare the timings.

```sql
-- Grab any AUTH_ID to use for the point lookup comparison.
SELECT AUTH_ID, AUTH_AMOUNT, MERCHANT_ID, AUTH_RESULT
FROM FISERV_PAYMENTS_DB.INTERACTIVE.AUTH_LOOKUP
LIMIT 1;
```

The interactive table will look **no better, and possibly worse**. Measured on this
dataset: standard 198ms elapsed and 37ms execution, interactive 289ms elapsed and 26ms
execution. It wins on execution and loses on elapsed, because a single query is dominated
by round trip.

> That single lookup did not show any advantage. Why not, and what would I have to change about the test to actually exercise the feature?

### Concurrency Load Test

**Prompt CoCo:**

> Run the load test at loadtest/interactive_concurrency_test.py with 150 queries and explain the results to me.

Expect roughly:

| | Standard | Interactive |
|---|---|---|
| Execution p50 | ~172 ms | **~17 ms** |
| Total queueing | **~108 s** | **0 ms** |

> Run it again at 100 queries. What happens to the queueing on each warehouse, and what does that tell me about how each one scales?

Standard queueing goes from about 35s at 100 queries to 108s at 150. A 1.5 times load rise
roughly triples the queueing, while interactive stays at 17ms and zero queue at both.

> The wall clock times were nearly identical. Why should I ignore that number?

Because the harness is client-bound on submission and polling. Quote execution and queue
time, which come from Snowflake, not wall clock, which comes from Python.

**Note:** interactive warehouses have a **five second statement timeout**. Scanning
`QUERY_HISTORY` on one fails with error 000630. Use `FISERV_WH` for anything that is not
a point lookup.

**What to take away:** the feature is about latency under concurrency. Demo it with one
query and you will conclude it does nothing, while measuring your own client.

## CoCo Custom Skill

**CoCo Custom Skills** let you package repeatable workflows into named commands that any team
member can invoke. A skill is a Markdown file at `.snowflake/cortex/skills/<name>/SKILL.md`
that defines triggers, parameters and step-by-step instructions CoCo follows when the skill is
activated.

Every check you have run this session was a prompt you had to remember. Make one permanent.

**Prompt CoCo:**

> Create a personal CoCo skill called payments-check that runs our standard data quality checks on this database: row counts against expected, NULL counts on the columns we know are dirty, whether every Dynamic Table is still INCREMENTAL, and whether processed volume reconciles between the raw tables and the dbt facts. Save it as a skill in this workspace.

### Test It

**Prompt CoCo:**

> Now invoke the skill and show me the output.

A good answer produces a skill that actually runs and returns output, not just a saved
file.

> Add one more check to the skill: warn me if any column with NULLs has no Data Metric Function attached to it.

That last check is the one that would have caught the Data Quality gap without anybody
thinking to look.

**What to take away:** the difference between knowing a check and having a check. Skills
are how a one-off investigation becomes something the next person inherits.

## Close

You have gone from not knowing the schema to a monitored, tested, incrementally refreshed
pipeline with a reusable quality check, without writing a script from scratch.

One set of numbers to carry into session 5:

| | |
|---|---|
| Processed volume | €461,744,970.59 |
| Total fees billed | €3,203,738.89 |
| **Net fee revenue** | **€1,934,149.64** |
| The naive join says | €1,565,500,000 |

That last figure is what happens when `FEE_LINES` fans out three to one and nobody checks.

Session 5 puts an agent on top of all of this and asks whether its answers can be trusted.
