# Session 5 — Agents, Governance and Evaluation

**Building an End-to-End Application Using CoCo on Snowflake**
*Fiserv Snowcamp, Dublin, 3 September 2026*

## Overview

Session 4 built a trustworthy pipeline. This session puts a Cortex Agent on top of it and
asks the harder question: how do you know the answers are right?

You will create an agent that orchestrates Cortex Analyst over a semantic view and Cortex
Search over free text, talk to it in Snowflake CoWork, run a Deep Research investigation,
see how a row access policy governs it without any change to the agent, ship it as a
Streamlit app, and then evaluate it against ground truth you derive by querying rather
than by assuming.

### What You'll Learn

- Build a Cortex Agent with Cortex Analyst (semantic view plus verified queries) and Cortex Search
- Write response instructions that stop the agent making three specific, expensive mistakes
- Use Snowflake CoWork for conversational analysis, Deep Research, Artifacts and Automations
- Implement transparent row-level security with Row Access Policies, and see the agent inherit it
- Ship the agent as a Streamlit app that inherits the same governance
- Evaluate agent quality with ground-truth datasets and LLM judges
- Read agent observability traces: reasoning steps, tool calls and token usage

### What You'll Build

A governed conversational interface over the payments platform from session 4, evaluated
against query-derived ground truth, exposed as an app, and observable in production.

### Prerequisites

- Session 4 completed. This session builds directly on it.
- A browser and your Snowflake account details.

### Table of Contents

1. Snowflake CoWork
2. Security and Governance
3. Streamlit Dashboard
4. Agent Evaluation
5. Agent Observability
6. Optional: MCP Server
7. Optional: MCP Server
8. Cleanup and Troubleshooting

## Snowflake CoWork

**Cortex Agents** are multi-tool AI orchestrators that route questions to the right data
source. They combine **Cortex Analyst** (text-to-SQL over Semantic Views) with **Cortex
Search** (vector plus keyword search over unstructured data) to answer both "what happened"
and "why" from a single conversational interface.

Your agent will have three tools: the semantic view, and one search service each over
merchant feedback and support cases.

### What the Semantic Layer Gives You

**Prompt CoCo:**

> What is in FISERV_PAYMENTS_DB.SEMANTIC? Explain what the semantic view gives me that querying the raw tables does not, and what the two Cortex Search services are for.

```sql
-- Pins role, database, schema and warehouse for every cell below. Re-run this if a
-- later cell cannot find an object.
USE ROLE ACCOUNTADMIN;
USE DATABASE FISERV_PAYMENTS_DB;
USE SCHEMA SEMANTIC;
USE WAREHOUSE FISERV_WH;
```

```sql
-- The semantic layer the agent will reason over.
SHOW SEMANTIC VIEWS IN SCHEMA FISERV_PAYMENTS_DB.SEMANTIC;
```

```sql
-- The two free-text indexes: merchant sentiment and support incidents.
SHOW CORTEX SEARCH SERVICES IN SCHEMA FISERV_PAYMENTS_DB.SEMANTIC;
```

A **semantic view** defines your metrics and joins once, so every agent and BI tool
resolves against the same definitions. Ours carries five **verified queries**: known-good
question and SQL pairs the agent can lean on rather than improvising.

### Create the Agent

**Prompt CoCo:**

> Create a Cortex Agent called FISERV_PAYMENTS_AGENT with three tools: the PAYMENTS_ANALYTICS semantic view for anything countable, and the two search services for merchant sentiment and support incidents. Give each tool a description that makes it obvious to the orchestrator when to use it rather than the others.

### The Part That Matters

**Prompt CoCo:**

> Now write the response instructions. This agent must not confuse total fees with net fee revenue, must use authorisation attempts as the denominator for approval rate, and must exclude declined transactions from processed volume. Be explicit, because these are the three mistakes it will otherwise make.

Without that instruction the agent reports the €3.2M of total fees as revenue instead of
the €1.9M actually retained, an overstatement of about 66 percent. **The instructions are
not decoration. They are the difference between a demo and a liability.**

### Test It in CoWork

Everything so far has been in Snowsight. From here on you talk to the agent itself, which happens
in **Snowflake CoWork**. That is also the only place you can see *which tool the agent chose and
why*.

Open it one of two ways:

- Navigate to **`https://ai.snowflake.com`**, or
- In Snowsight, go to **AI & ML > Agents**, select your agent, and choose **Preview in Snowflake CoWork**

CoWork starts your session with your **default role and default warehouse**, not whatever you had
selected in Snowsight. If the agent cannot reach anything, check those first with the pickers in
the CoWork interface.

Your agent should appear in the list automatically. Select it, then start by checking whether the
instructions you just wrote actually landed.

**Prompt CoWork:**

> What was our net fee revenue for the whole period?

```sql
-- The answer key. Derive it, do not assume it.
SELECT ROUND(SUM(CASE WHEN FEE_CATEGORY = 'Pass-through' THEN 0
                      ELSE FEE_AMOUNT_EUR END), 2) AS NET_FEE_REVENUE_EUR,
       ROUND(SUM(FEE_AMOUNT_EUR), 2)               AS TOTAL_FEES_EUR
FROM FISERV_PAYMENTS_DB.RAW.FEE_LINES;
```

Correct answer: **€1,934,149.64**. If you get €3,203,738.89, your instructions did not
land. Go back and make them explicit.

### Test Agent Routing

Three more questions, still in CoWork, escalating deliberately: a simple lookup, a genuine
multi-tool investigation, then a question the agent should refuse.

**Prompt CoWork:**

> Which month had the lowest approval rate and what was it?

**August 2025 at 88.02 percent**, against roughly 93.98 to 93.99 percent in the other
three months.

Now the capstone question:

> Approval rates dipped in August. What happened, and does the merchant-facing evidence agree?

Watch which tools it reaches for in the trace. You are looking for *which* tool fired and *why*,
not just the answer. A good answer quantifies the dip from the semantic view,
finds that **Issuer Unavailable rose to 38.1 percent of declines from a baseline of 5.0
percent**, and then corroborates it from support cases and merchant feedback written in
August. The numbers and the narrative agree, and the cause turns out to be upstream of
Fiserv: not a terminal fault and not the gateway.

Then ask something it should refuse:

> What will our approval rate be next March?

The data ends September 2025. A good agent says so. A bad one extrapolates confidently.

### Deep Research

> **Not yet verified.** Deep Research is a CoWork interface feature with no SQL surface, so
> it could not be tested before the workshop. If it behaves differently from what follows,
> tell your facilitator: that is useful information, not a failure on your part.

**Deep Research** runs a multi-step investigation rather than answering in one shot. It
plans, gathers from several sources, and returns a report with citations.

Still in CoWork, select the **+** button in the message bar and choose **Deep Research**.

**Prompt CoWork:**

> Investigate the August 2025 approval rate dip end to end. Quantify it, identify the dominant decline reason and how far it moved from baseline, check whether merchant feedback and support cases from August corroborate it, and tell me whether the cause is inside or outside Fiserv's control.

**Investigations can take up to 10 minutes.** That is expected, not a hang. Start it, then read
the next section while it runs rather than watching the spinner. Once the report is ready it stays
in context for the rest of the thread, so follow-ups like "break that down by region" run as
normal chat turns without restarting the investigation.

Expect it to cite both the structured figures and specific pieces of free text. Compare its answer
to the one you got from the single capstone question above: the interesting part is whether the
extra steps changed the conclusion or only the amount of supporting evidence.

### Save as Artifact

> **Not yet verified.** As above.

Save the Deep Research result as an **Artifact**, which makes it a governed object others
can open rather than a message in your chat history.

Then establish what governance travelled with it:

**Prompt CoWork:**

> Who can see this artifact, and does the row access policy on RAW.MERCHANTS still apply to whoever opens it?

That question matters more than the saving. An artifact that captured
`ACCOUNTADMIN`-visible numbers and is then shared with a regional role would be a
governance hole, and you want to know which way it works before you rely on it.

### Set Up an Automation

> **Not yet verified.** As above.

An **Automation** runs an agent request on a schedule, so an investigation becomes a
recurring report.

Create one that runs the approval-rate check weekly:

**Prompt CoWork:**

> Every Monday at 08:00, report processed volume, approval rate and net fee revenue for the previous week, and flag any decline reason that has moved more than five percentage points from its four-week average.

The flag threshold is the point. A scheduled report nobody reads is worse than no report;
a scheduled report that only speaks up when something moved is a control.

## Security and Governance

**Row Access Policies** enforce row-level security declaratively. You define a boolean
expression that determines which rows are visible to which roles, and Snowflake applies it
transparently to every query, including those generated by AI agents. No application code
changes required.

Because the policy is attached to the table, everything reading that table inherits it: SQL
you write by hand, the agent, and any app built on top.

One interaction worth knowing, since this workshop uses both features: a row access policy
that calls context functions can block **incremental** refresh on a dynamic table built over
that table. Ours does not, which is why all five dynamic tables are still incremental, but it
is the first thing to check if a pipeline silently downgrades to full refresh.

**Prompt CoCo:**

> There is a row access policy on RAW.MERCHANTS. Explain what it does and how it decides what a caller can see.

```sql
-- Where the policy is attached. POLICY_REFERENCES is a table function, not a view.
SELECT POLICY_NAME, REF_ENTITY_NAME, REF_COLUMN_NAME, POLICY_STATUS
FROM TABLE(FISERV_PAYMENTS_DB.INFORMATION_SCHEMA.POLICY_REFERENCES(
    POLICY_NAME => 'FISERV_PAYMENTS_DB.SEMANTIC.ACQUIRING_REGION_POLICY'));
```

It keys on `CURRENT_ROLE()`. `ACCOUNTADMIN` and `SYSADMIN` see everything;
`SOUTHERN_EUROPE_MANAGER` sees Southern Europe only.

**Prompt CoCo:**

> Show me merchant counts by acquiring region as my current role, then explain what the same query would return as SOUTHERN_EUROPE_MANAGER.

```sql
-- Run this as your own role now, and note the numbers. The facilitator will run the
-- identical query as SOUTHERN_EUROPE_MANAGER and get a different answer.
SELECT ACQUIRING_REGION, COUNT(*) AS MERCHANTS
FROM FISERV_PAYMENTS_DB.RAW.MERCHANTS
GROUP BY ACQUIRING_REGION
ORDER BY MERCHANTS DESC;
```

Four regions and 2,000,000 merchants as `ACCOUNTADMIN`. **699,882 and one region** as the
regional role.

### Verify Through CoWork

**Facilitator demo.** Your facilitator will sign in as a second user holding
`SOUTHERN_EUROPE_MANAGER` and ask the agent the same August question you asked earlier.
Same agent, same question, different answer, because the policy applies to the SQL the
agent *generates*, not only to SQL you write yourself.

**Prompt CoCo:**

> If the policy filters what the agent can see, what does that mean for evaluating the agent?

This matters for the next step. Evaluations do not pass session attributes, so an agent
whose results depend on them cannot be evaluated meaningfully. Ours keys on
`CURRENT_ROLE()` and the evaluation runs as your role, which is why it works here. A policy
built on session variables would quietly break it.

## Streamlit Dashboard

**Streamlit in Snowflake** lets you build and deploy interactive data applications directly
within your Snowflake account, with no external infrastructure. Apps run securely inside
Snowflake with native access to your data, governed by role-based access control.

Exactly *whose* role governs them is the question this section ends on, and it is not the one
most people expect.

**Prompt CoCo:**

> Build me a Streamlit app in this account with two tabs. First tab: a dashboard of processed volume and approval rate by month and region, from the semantic view. Second tab: a chat box that talks to FISERV_PAYMENTS_AGENT.

> Make the August dip obvious on the dashboard without me having to hunt for it.

> Run it and fix anything that breaks.

> Who can see what in this app if I share it with a colleague who only holds SOUTHERN_EUROPE_MANAGER?

**Do not take CoCo's answer on trust. Test it.** Share the app with your second login, open
it as `SOUTHERN_EUROPE_MANAGER`, and read the merchant count off the dashboard.

```sql
-- What the app SHOULD show a regional colleague, if the policy followed them.
USE ROLE SOUTHERN_EUROPE_MANAGER;
SELECT COUNT(*) AS MERCHANTS_VISIBLE FROM FISERV_PAYMENTS_DB.RAW.MERCHANTS;
USE ROLE ACCOUNTADMIN;
```

Run as the regional role directly, that returns **699,882**. Now compare it against what the
shared app displays.

**They will not match.** The app shows all **2,000,000** merchants.

Streamlit in Snowflake runs with the **owner's rights** by default, not the viewer's. The
query inside the app executes as you, the owner, so the row access policy is evaluated
against `ACCOUNTADMIN` regardless of who is looking at the screen. Your colleague sees
everything.

> I expected the row access policy to apply to whoever opens the app, but it is showing all 2,000,000 merchants. Explain why, and what I would have to change.

The fix is **Restricted Caller's Rights**, which makes the app execute with the caller's role
so policies evaluate against the person viewing. It is deliberately not the default.

**What to take away:** governance defined once at the table did follow the pipeline and the
agent, and it is genuinely worth having. But it stopped at the app boundary, and nothing
warned you. "The policy applies everywhere" was a reasonable assumption that happened to be
wrong, and the only way you found out was by checking a number.

## Agent Evaluation

**Agent evaluation** scores an agent's answers against ground truth you supply, and reports
per-metric results you can act on. The metric to understand before you start is **tool
selection accuracy**: it divides by `max(expected, actual)`, so calling an *extra* tool is
penalised exactly as hard as missing a required one.

That matters because a red metric is a **question, not a verdict**. More often than not the
answer key is wrong, not the agent. You are about to find two of yours are.

One limitation to know: evaluations do not pass session attributes, so the row access policy
from the previous section does not apply during a run. Evaluate as the owner, not as a
regional role.

The agent gives confident answers. That is not evidence that they are right.

**Prompt CoCo:**

> I want to evaluate this agent properly. Build me an evaluation set of seven questions covering monthly approval rate, net fee revenue, low-rated feedback about settlement delays, volume by region, August decline reasons, volume by merchant segment, and the August investigation.

### The Discipline

**Prompt CoCo:**

> For each question, derive the expected answer by running a query against the data. Do not write the expected answer from what you assume is true.

Take this seriously. Building this set, **two answer keys turned out to be wrong**:

```sql
-- Largest segment by volume. The intuitive answer is Enterprise. It is not.
SELECT m.MERCHANT_SEGMENT,
       ROUND(SUM(a.AUTH_AMOUNT) / 1000000, 1) AS VOLUME_EUR_M
FROM FISERV_PAYMENTS_DB.RAW.AUTHORISATIONS a
JOIN FISERV_PAYMENTS_DB.RAW.MERCHANTS m
  ON a.MERCHANT_ID = m.MERCHANT_ID
WHERE a.AUTH_RESULT = 'Approved'
GROUP BY m.MERCHANT_SEGMENT
ORDER BY VOLUME_EUR_M DESC;
```

The largest segment is **SMB at €216.5M**, not Enterprise. Enterprise is the most
*concentrated* per merchant, which is a different claim. An evaluation asserting the wrong
one would have failed a correct agent.

### Run via Snowsight UI

Go to **AI & ML → Agents**, select `FISERV_PAYMENTS_AGENT`, open the **Evaluations** tab,
and create a run with answer correctness, logical consistency and tool selection accuracy.

Or run it with SQL:

```sql
-- Start the evaluation run. This takes a few minutes: the agent answers every question
-- and LLM judges then score each answer.
CALL EXECUTE_AI_EVALUATION(
  'START',
  OBJECT_CONSTRUCT('run_name', 'workshop-run-1'),
  '@FISERV_PAYMENTS_DB.SEMANTIC.EVAL_CONFIG/agent_evaluation_config.yaml'
);
```

```sql
-- Per-question scores once the run completes.
SELECT INPUT, METRIC_NAME, EVAL_AGG_SCORE
FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_EVALUATION_DATA(
    'FISERV_PAYMENTS_DB', 'SEMANTIC', 'FISERV_PAYMENTS_AGENT',
    'CORTEX AGENT', 'workshop-run-1'))
ORDER BY INPUT, METRIC_NAME;
```

### Interpret Results

**Prompt CoCo:**

> Tool selection accuracy scored badly on the August investigation question. Is the agent wrong, or is my evaluation wrong?

The evaluation is wrong. Tool selection accuracy scores matched tools over
`max(expected, actual)`, so **extra tool calls are penalised**. An open investigative
question legitimately makes five to ten calls, and a fixed expected-tool list cannot match
them. The same question scores 1.0 on answer correctness. Judge narrow questions on tool
selection and investigative ones on correctness and consistency.

**Do not pad the expected-tool list to lift the score.** That teaches you to game the
metric.

**Prompt CoCo:**

> One of my questions scored 0.67 on answer correctness even though the agent's numbers look right to me. Check whether my ground truth demanded something the question never asked for.

Over-specified ground truth manufactures false failures. This exact thing happened: the
answer key demanded merchant counts for a question that only asked which segment was
largest.

### Improve Scores

**Prompt CoCo:**

> Improve the agent based on what the evaluation found, then re-run and compare the two runs.

**What to take away:** an evaluation is a test suite for an agent, and like any test suite
it can be wrong in ways that look like the code is wrong. A red metric is a question, not
a verdict.

## Agent Observability

**Agent observability** records what an agent actually did: the tools it chose, the inputs it
passed them, how long each step took, and how many tokens it burned. Where evaluation asks
*was the answer right*, observability asks *how was it produced*. Traces are organised as
thread, turn, trace and span, so you can open a single conversation and walk down into an
individual tool call.

Two things determine what you see. **Evaluation runs do not populate it** — only real
conversations do. And depth is gated by the `READ UNREDACTED AI OBSERVABILITY EVENTS TABLE`
account privilege: without it you get tool names, latency and token counts, but not tool
inputs or conversation text.

> **Partly verified.** The SQL below runs correctly, but it returned **zero rows** when
> tested, because the agent had only ever been evaluated. Evaluation traces go to a
> separate path. Production observability populates only from real conversations, which is
> why this step comes after you have used CoWork.

Where evaluation scores an agent on a dataset, **observability** shows you what actually
happened in real conversations: planning, tool calls, latency, token usage and user
feedback.

**Prompt CoCo:**

> Show me the observability events for FISERV_PAYMENTS_AGENT from the conversations we have had today.

```sql
-- Production conversation traces. Expect ZERO rows until you have actually talked to
-- the agent in CoWork: evaluation runs write to a different path entirely.
SELECT TIMESTAMP,
       RECORD:name::VARCHAR      AS EVENT_NAME,
       TRACE:trace_id::VARCHAR   AS TRACE_ID
FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(
    'FISERV_PAYMENTS_DB', 'SEMANTIC', 'FISERV_PAYMENTS_AGENT', 'CORTEX AGENT'))
ORDER BY TIMESTAMP DESC
LIMIT 50;
```

### View Reasoning Steps and Token Usage

In Snowsight, go to **AI & ML → Agents**, select the agent, and open the **Observability**
tab. Each row is a conversation thread. Open one and you get a trace per turn, with a span
for planning, a span per tool call, and a span for response generation.

One conversation is a **thread**. One question and its answer is a **turn**, which is one
**trace**. Each step inside it is a **span**.

### View Tool Calls

**Prompt CoCo:**

> For the August investigation question, show me every tool the agent called and how many tokens each step used.

**A privilege you may hit.** An account-level privilege,
`READ UNREDACTED AI OBSERVABILITY EVENTS TABLE`, controls whether you can see full tool
inputs and outputs and full conversation text. Without it you still get metadata: tool
names, token usage, latency and errors. If the traces look thinner than expected, that is
why, and it is a deliberate default rather than a fault.

## Optional: MCP Server

**Facilitator demo, if time allows.** An **MCP server** exposes your agent over an open
protocol so any AI client can call it: the same agent, the same governance, a different
front door.

One constraint worth naming, because it rules out combining this with the previous section:
**evaluations do not support MCP servers as tools.** You can evaluate the agent, and you can
expose the agent over MCP, but you cannot evaluate the MCP surface itself.

**Prompt CoCo:**

> Explain what an MCP server exposes in Snowflake and what I would use one for.

> If I exposed this agent over MCP, what governance still applies and what becomes my responsibility?

Worth knowing before you build on it: **agent evaluations do not currently support MCP
servers as tools.** The run completes, but no MCP tool is called, so the results say
nothing about that path.

## Cleanup and Troubleshooting

Nothing needs cleaning up. Your account is yours, and the objects are worth keeping if you
want to carry on afterwards. If you do want to reset:

```sql
-- Suspends compute without destroying anything you built.
ALTER WAREHOUSE FISERV_WH SUSPEND;
ALTER WAREHOUSE FISERV_GEN2_WH SUSPEND;
```

| Symptom | Cause |
|---|---|
| Error 000630 on an interactive warehouse | Five second statement timeout. Use `FISERV_WH` for anything that is not a point lookup |
| Agent reports €3.2M as revenue | Response instructions did not land. Rewrite them explicitly |
| Evaluation scores 0.0 on tool selection | Usually the expected-tool list, not the agent |
| Observability tab is empty | No real conversations yet. Evaluations do not populate it |
| A dynamic table refreshes FULL | Refresh mode was not set explicitly; Snowflake judged the query complex |

## Close

Across two sessions you built a monitored, tested pipeline; put a governed agent on top of
it; proved its answers against query-derived ground truth; found that two of your own
answer keys and one of your metrics were wrong; and shipped it as an app.

The recurring lesson is the one worth taking back: **the failure mode in all of this is not
an error message. It is a plausible number.** The fan-out that triples volume, the monitor
on the wrong column, the refresh mode you did not set, total fees reported as revenue, and
an evaluation that fails a correct answer. None of them threw an error. Every one returned
something that looked completely fine.
