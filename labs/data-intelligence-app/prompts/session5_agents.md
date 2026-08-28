# Session 5 — Data & Analytics with AI: Agents and Talk to your Data

**60 minutes. Six modules. Everything is a prompt.**

Session 4 built a trustworthy pipeline. This session puts an agent on top of it, then asks the
harder question: how do you know the answers are right?

---

## Module 1 — Build the agent (12 min)

**Prompt 1.1**
> What is in FISERV_PAYMENTS_DB.SEMANTIC? Explain what the semantic view gives me that
> querying the raw tables does not, and what the two Cortex Search services are for.

**Prompt 1.2**
> Create a Cortex Agent called FISERV_PAYMENTS_AGENT with three tools: the PAYMENTS_ANALYTICS
> semantic view for anything countable, and the two search services for merchant sentiment
> and support incidents. Give each tool a description that makes it obvious to the
> orchestrator when to use it rather than the others.

**Prompt 1.3 — the part that matters**
> Now write the response instructions. This agent must not confuse total fees with net fee
> revenue, must use authorisation attempts as the denominator for approval rate, and must
> exclude declined transactions from processed volume. Be explicit, because these are the
> three mistakes it will otherwise make.

Without that third prompt the agent will report the €3.2M of total fees as revenue instead of
the €1.9M actually retained — an overstatement of about 66%. **The instructions are not
decoration. They are the difference between a demo and a liability.**

**Prompt 1.4**
> Ask the agent what our net fee revenue was for the whole period.

Correct answer: **€1,934,149.64**. If you get €3,203,738.89, your instructions did not land —
go back to 1.3.

---

## Module 2 — Talk to your data, and route it (10 min)

**Prompt 2.1**
> Ask the agent which month had the lowest approval rate and what it was.

**August 2025, 88.02%**, against roughly 93.98–93.99% in the other three months.

**Prompt 2.2 — the capstone question**
> Ask the agent: approval rates dipped in August. What happened, and does the merchant-facing
> evidence agree?

Watch which tools it reaches for. A good answer quantifies the dip from the semantic view,
finds that **Issuer Unavailable rose to 38.1% of declines from a baseline of 5.0%**, and then
corroborates it from support cases and merchant feedback written in August. The numbers and
the narrative agree, and the cause turns out to be upstream of Fiserv — not a terminal fault
and not the gateway.

**Prompt 2.3**
> Ask it something it should refuse: what will our approval rate be next March?

The data ends September 2025. A good agent says so. A bad one extrapolates confidently.

**Prompt 2.4 — open the agent in Snowflake CoWork.** Ask the same August question there and
watch the tool routing in the trace. You are looking for *which* tool fired and *why*, not
just the answer.

---

## Module 3 — Governance the agent inherits (8 min)

**Prompt 3.1**
> There is a row access policy on RAW.MERCHANTS. Explain what it does and how it decides what
> a caller can see.

It keys on `CURRENT_ROLE()`. `ACCOUNTADMIN` and `SYSADMIN` see everything;
`SOUTHERN_EUROPE_MANAGER` sees Southern Europe only.

**Prompt 3.2**
> Show me merchant counts by acquiring region as my current role, then explain what the same
> query would return as SOUTHERN_EUROPE_MANAGER.

Four regions and 2,000,000 merchants as ACCOUNTADMIN. **699,882 and one region** as the
regional role.

**Facilitator demo.** Your facilitator will sign in as a second user holding
`SOUTHERN_EUROPE_MANAGER` and ask the agent the same question you asked in Module 2. Same
agent, same question, different answer — because the policy applies to the SQL the agent
generates, not just to SQL you write by hand.

**Prompt 3.3**
> If the policy filters what the agent can see, what does that mean for evaluating the agent?

This matters for the next module. Evaluations do not pass session attributes, so an agent
whose results depend on them cannot be evaluated meaningfully. Ours keys on `CURRENT_ROLE()`
and the evaluation runs as your role, which is why it works here — but a policy built on
session variables would quietly break it.

---

## Module 4 — Evaluate the agent (15 min)

The agent gives confident answers. That is not evidence that they are right.

**Prompt 4.1**
> I want to evaluate this agent properly. Build me an evaluation set of seven questions
> covering monthly approval rate, net fee revenue, low-rated feedback about settlement
> delays, volume by region, August decline reasons, volume by merchant segment, and the
> August investigation.

**Prompt 4.2 — the discipline**
> For each question, derive the expected answer by running a query against the data. Do not
> write the expected answer from what you assume is true.

Take this seriously. Building this set, **two answer keys turned out to be wrong**: the
largest segment by volume is **SMB at €216.5M**, not Enterprise — Enterprise is the most
concentrated per merchant, which is a different claim. And the count of low-rated settlement
feedback is 134, not the 180 in the original notes. An eval asserting either wrong value would
have failed a correct agent.

**Prompt 4.3**
> Now run the evaluation with answer correctness, logical consistency and tool selection
> accuracy, and show me the scores.

**Prompt 4.4**
> Tool selection accuracy scored badly on the August investigation question. Is the agent
> wrong, or is my evaluation wrong?

The evaluation is wrong. That metric scores matched tools over
`max(expected, actual)`, so **extra tool calls are penalised**. An open investigative question
legitimately makes five to ten calls, and a fixed expected-tool list cannot match them. The
same question scores 1.0 on answer correctness. Judge narrow questions on tool selection and
investigative ones on correctness and consistency.

**Do not pad the expected-tool list to lift the score.** That teaches you to game the metric.

**Prompt 4.5**
> One of my questions scored 0.67 on answer correctness even though the agent's numbers look
> right to me. Check whether my ground truth demanded something the question never asked for.

Over-specified ground truth manufactures false failures. This exact thing happened: the answer
key demanded merchant counts for a question that only asked which segment was largest.

**Prompt 4.6**
> Improve the agent based on what the evaluation found, then re-run and compare the two runs.

**What to take away:** an evaluation is a test suite for an agent, and like any test suite it
can be wrong in ways that look like the code is wrong. A red metric is a question, not a
verdict.

---

## Module 5 — MCP (5 min, facilitator demo)

Your facilitator will connect an external MCP client to this account and ask the agent a
question from outside Snowsight — the same agent, the same governance, a different front door.

**Prompt 5.1**
> Explain what an MCP server exposes in Snowflake and what I would use one for.

**Prompt 5.2**
> If I exposed this agent over MCP, what governance still applies and what becomes my
> responsibility?

Worth knowing before you build on it: **agent evaluations do not currently support MCP servers
as tools.** The run completes, but no MCP tool is called, so the results say nothing about
that path.

---

## Module 6 — Ship it as a Streamlit app (10 min)

**Prompt 6.1**
> Build me a Streamlit app in this workspace with two tabs. First tab: a dashboard of
> processed volume and approval rate by month and region, from the semantic view. Second tab:
> a chat box that talks to FISERV_PAYMENTS_AGENT.

**Prompt 6.2**
> Make the August dip obvious on the dashboard without me having to hunt for it.

**Prompt 6.3**
> Run it and fix anything that breaks.

**Prompt 6.4**
> Who can see what in this app if I share it with a colleague who only holds
> SOUTHERN_EUROPE_MANAGER?

The row access policy follows them into the app. Governance defined once at the table applies
to the pipeline, the agent, and the app — you did not have to reimplement it three times.

---

## Close

Across two sessions you built a monitored, tested pipeline; put a governed agent on top of it;
proved the agent's answers against query-derived ground truth; found that two of your own
answer keys and one of your metrics were wrong; and shipped it as an app.

The recurring lesson is the one worth taking back: **the failure mode in all of this is not an
error message. It is a plausible number.** The fan-out that triples volume, the monitor on the
wrong column, the refresh mode you did not set, total fees reported as revenue, and an
evaluation that fails a correct answer — none of them threw an error. Every one of them
returned something that looked fine.
