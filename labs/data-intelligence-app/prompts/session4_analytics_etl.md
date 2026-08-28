# Session 4 — Data & Analytics with AI: Analytics and ETL

**75 minutes. Seven modules. Everything is a prompt.**

You will not paste SQL scripts or hunt through menus. You type a request to CoCo in a
Snowsight Workspace, read what it proposes, and decide whether it is right. That decision is
the skill this session is teaching — the typing is not the hard part.

## Before you start

1. Open Snowsight, go to **Projects → Workspaces**, open your workspace.
2. Confirm `AGENTS.md` is in the workspace. CoCo reads it automatically, so it already knows
   the payments domain, the schemas, and the definitions that are easy to get wrong.
3. Confirm your setup finished:

> Run the verification script at generators/99_verify_setup.sql and show me any row that
> does not say PASS.

Every row must say PASS. If any row fails, tell your facilitator now rather than debugging
into the session.

**If a prompt goes wrong at any point**, do not reach for a script. Say what happened:

> That is not what I expected. I wanted X but I got Y. Explain what went wrong and fix it.

CoCo has the full context. Recovery is a conversation, not a fallback file.

---

## Module 1 — Explore the data (8 min)

The point of this module is that you can start from ignorance and reach a defensible number
without knowing the schema.

**Prompt 1.1**
> I am new to this data. Describe what is in FISERV_PAYMENTS_DB.RAW, how the tables relate to
> each other, and the grain of each one.

**Prompt 1.2**
> What was our total processed volume for the whole period, and how does it split by
> acquiring region?

Expect roughly **€461.7M** total, with Southern Europe largest at about €164.3M.

**Prompt 1.3 — the trap.** Ask this deliberately badly:
> Join AUTHORISATIONS to FEE_LINES and give me total processed volume by region.

Read the answer carefully. If the number comes back near **€1,565M** rather than €461.7M, the
fan-out has inflated it roughly 3.4x. Push back:
> That looks about three times too high. Explain why, and give me the correct figure.

**What to take away:** a plausible number is not a correct number. The fan-out is invisible
unless you know the grain.

---

## Module 2 — Data quality with Data Metric Functions (12 min)

**Prompt 2.1**
> What Data Metric Functions are attached to tables in FISERV_PAYMENTS_DB.RAW, and what are
> they monitoring?

**Prompt 2.2**
> Show me the latest results from those monitors. Are any of them reporting violations?

You will see NULLs reported on `AUTH_AMOUNT` and `FEE_AMOUNT_EUR`, and a clean result on
`FEE_CATEGORY`. At this point the data looks like it has two known issues, both watched.

**Prompt 2.3 — the real exercise**
> Check every column in FEE_LINES for NULLs, not just the monitored ones. Is anything
> unmonitored also broken?

`FEE_TYPE` has **152 NULLs and no monitor on it**. The monitor was attached to
`FEE_CATEGORY`, the column next to it, which is completely clean. Two monitors, both green-ish,
and the actual problem sitting in the gap between them.

**Prompt 2.4**
> Move the monitor to where it should have been, and tell me what the count is once it runs.

**What to take away:** a monitor tells you about the column it is attached to and nothing
else. Coverage is a decision, and yours was wrong. This is the most common data quality
failure in production and it never shows up as an error.

---

## Module 3 — The Dynamic Tables pipeline (12 min)

**Prompt 3.1**
> Explain the Dynamic Table pipeline in FISERV_PAYMENTS_DB.DYNAMIC_TABLES. Draw the
> dependency graph, and tell me the target lag and refresh mode of each table.

Five tables in three tiers. Tiers 1 and 2 have a one-minute lag, tier 3 uses `DOWNSTREAM`.

**Prompt 3.2**
> Why is every one of these INCREMENTAL rather than FULL, and what would have happened if I
> had not set the refresh mode explicitly?

This is the point of the module. Snowflake looks at the query, decides the tier 1 joins are
"complex", and **silently sets refresh mode to FULL**. That then cascades: tier 2 fails to
build at all, because change tracking is not supported on a dynamic table that refreshes
FULL. A pipeline that appears to work can be quietly reprocessing everything on every cycle.

**Prompt 3.3**
> Add a new tier 3 dynamic table showing chargeback rate by merchant segment and month.
> Make sure it refreshes incrementally, and prove to me that it does.

**Prompt 3.4**
> Insert a handful of new authorisations into RAW.AUTHORISATIONS and show me the change
> flowing through all three tiers.

**What to take away:** declarative does not mean unexamined. Always check the refresh mode
you actually got, not the one you assumed.

---

## Module 4 — dbt (15 min)

**Prompt 4.1**
> There is a dbt project in this workspace. Explain its structure: what the staging models
> do, what the analytics models do, and what the tests check.

**Prompt 4.2**
> Run the whole project and tests.

**It will fail. That is the exercise.** 31 tests pass, 2 fail:
`not_null_fct_fee_economics_net_fee_revenue_eur` (60 rows) and
`not_null_fct_merchant_performance_processed_volume_eur` (42 rows).

**Prompt 4.3**
> Two tests failed. Do not fix them yet. Explain exactly why they failed and trace the cause
> back to the source data.

The chain to look for: 215 NULL fee amounts and 189 NULL auth amounts in the raw tables land
in aggregate groups where **every** row is NULL, and `SUM()` of an all-NULL group returns
NULL, not 0. So 404 bad source rows become 102 broken aggregate rows. **The models are
correct. The data is not.**

**Prompt 4.4**
> Now fix it. I want the money to still reconcile, and I want the fix to make the missing
> data visible rather than hiding it. Explain the tradeoff in whatever you choose.

There is more than one defensible answer here. Coalescing to zero makes the build pass but
buries the problem. Excluding the rows changes the totals. Splitting out an explicit
"unknown" bucket keeps both the total and the visibility. Argue it out with CoCo.

**Prompt 4.5**
> Re-run the project and confirm we are green. Then add a test that would have caught this at
> the staging layer instead of three models downstream.

**What to take away:** a failing test is information. The instinct to make the red go away is
what turns a data quality problem into a reporting problem.

---

## Module 5 — Gen2 warehouses (8 min)

**Prompt 5.1**
> Compare FISERV_WH and FISERV_GEN2_WH. What is different about them?

**Prompt 5.2**
> Write me an expensive analytical query over AUTHORISATIONS and FEE_LINES — something with
> real joins and aggregation, not a point lookup. Run it on both warehouses and compare
> execution time, not elapsed time. Run each one twice and use the second run, so I am not
> measuring warehouse resume.

**Prompt 5.3**
> Is that difference big enough to justify moving our ETL to Gen2? What would you need to
> measure over a week to answer that properly?

**What to take away:** one query on an idle warehouse is not a benchmark. Be honest about
what a single measurement can and cannot tell you.

---

## Module 6 — Interactive Tables under concurrency (12 min)

**Prompt 6.1**
> Explain the difference between INTERACTIVE.AUTH_LOOKUP and INTERACTIVE.STD_AUTH_LOOKUP.
> Why does one need a clustering key and the other does not?

**Prompt 6.2 — the measurement that misleads**
> Pick one AUTH_ID and query it from both tables. Compare the timings.

The interactive table will look **no better, and possibly worse**. Measured on this dataset:
standard 198ms elapsed / 37ms execution, interactive 289ms elapsed / 26ms execution. It wins
on execution and loses on elapsed, because a single query is dominated by round trip.

**Prompt 6.3**
> That single lookup did not show any advantage. Why not, and what would I have to change
> about the test to actually exercise the feature?

**Prompt 6.4**
> Run the load test at loadtest/interactive_concurrency_test.py with 150 queries and explain
> the results to me.

Expect roughly:

| | Standard | Interactive |
|---|---|---|
| Execution p50 | ~172 ms | **~17 ms** |
| Total queueing | **~108 s** | **0 ms** |

**Prompt 6.5**
> Run it again at 100 queries. What happens to the queueing on each warehouse, and what does
> that tell me about how each one scales?

Standard queueing goes from about 35s at 100 queries to 108s at 150 — a 1.5x load rise
roughly triples the queueing. Interactive stays at 17ms and zero queue at both.

**Prompt 6.6**
> The wall clock times were nearly identical. Why should I ignore that number?

Because the test harness is client-bound on submission and polling. Quote execution and queue
time, which come from Snowflake, not wall clock, which comes from Python.

**What to take away:** the feature is about latency under concurrency. If you demo it with one
query you will conclude it does nothing, and you will be measuring your own client.

---

## Module 7 — Build your own CoCo skill (8 min)

Every check you have run this session was a prompt you had to remember. Make one permanent.

**Prompt 7.1**
> Create a personal CoCo skill called payments-check that runs our standard data quality
> checks on this database: row counts against expected, NULL counts on the columns we know
> are dirty, whether every Dynamic Table is still INCREMENTAL, and whether processed volume
> reconciles between the raw tables and the dbt facts. Save it as a skill in this workspace.

**Prompt 7.2**
> Now invoke the skill and show me the output.

**Prompt 7.3**
> Add one more check to the skill: warn me if any column with NULLs has no Data Metric
> Function attached to it.

That last check is the one that would have caught Module 2's gap without anybody thinking to
look.

**What to take away:** the difference between knowing a check and having a check. Skills are
how a one-off investigation becomes something the next person inherits.

---

## Close

You have gone from not knowing the schema to a monitored, tested, incrementally refreshed
pipeline with a reusable quality check — without writing a script from scratch. Session 5
puts an agent on top of it and asks whether the answers can be trusted.
