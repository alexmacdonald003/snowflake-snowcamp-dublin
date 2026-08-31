# Snowflake SnowCamp Dublin

Hands-on lab material for a two-day Snowflake workshop. Everything here runs in a browser
against your own Snowflake account. There is nothing to install.

**Day 2 lab guide:**
https://alexmacdonald003.github.io/snowflake-snowcamp-dublin/labs/data-intelligence-app/guide/fiserv_workshop_day2.html

## Start here

1. Open a Snowsight worksheet on your workshop account.
2. Paste in [`bootstrap.sql`](bootstrap.sql) and run it.
3. Confirm the final `LS` returns rows.

That connects this repo to your account as a Snowflake **git repository**, so every lab
script and data file below is readable directly from SQL. It is the only copy-and-paste step
in the workshop.

## The two days

**Day one — Snowflake 101**, three sessions. Warehouses and where speed actually comes from,
transformations, zero-copy cloning and Time Travel, semi-structured data, governance, and AI
over free text with a single SQL function.

Open the notebooks in Snowsight:

| Session | Notebook |
|---|---|
| Part 1 | `labs/101/notebooks/101_part1.ipynb` |
| Part 2 | `labs/101/notebooks/101_part2.ipynb` |
| Part 3 | `labs/101/notebooks/101_part3.ipynb` |

Part 1 begins by building your environment. Run its first three cells and let the second one
work in the background: it builds day two's data, which takes about six minutes, and starting
it now means you are not waiting tomorrow morning.

**Day two — building and governing an AI data application**, two sessions in one guide:

### [Open the day 2 lab guide](https://alexmacdonald003.github.io/snowflake-snowcamp-dublin/labs/data-intelligence-app/guide/fiserv_workshop_day2.html)

It covers dynamic table pipelines, dbt, data quality monitoring, Gen2 warehouses,
interactive tables, Cortex Agents, row-level security, agent evaluation and observability.

If the venue wifi lets you down, the guide works offline too: open
`labs/data-intelligence-app/guide/fiserv_workshop_day2.html` in this repo, choose **Download
raw file**, and open it from your Downloads folder. It has no external dependencies, so it
renders with no network at all.

There is a clearly marked stopping point partway through where session four ends. Do not
carry on past it until after the break.

A notebook version of the same material is in `labs/data-intelligence-app/notebooks/` if you
prefer to stay inside Snowsight.

## How the labs work

Every step gives you two paths: a **prompt** to type into Snowflake CoCo, and the **SQL** it
should produce. Both reach the same place.

Running the SQL is quicker. Prompting teaches you more, and it is what the workshop is
actually about — so prompt first, then compare CoCo's answer against the SQL underneath. Where
they differ, work out which is right and why. Some of the time, neither is.

Expected results are stated throughout. If your number does not match, that is worth
investigating rather than ignoring: several of the exercises are built around results that
look perfectly reasonable and are wrong.

## Layout

```
bootstrap.sql                          Connect this repo to your account. Start here
labs/101/notebooks/                    Day one, sessions 1 to 3
labs/101/generators/                   Day one environment build and verification
labs/data-intelligence-app/guide/      Day two guide, HTML and markdown source
labs/data-intelligence-app/notebooks/  Day two as notebooks
labs/data-intelligence-app/generators/ Day two environment build and verification
data/                                  Text corpora loaded during setup
```

## If something breaks

Re-run the verification for the day you are on. Every row must say `PASS`:

```sql
-- Day one
EXECUTE IMMEDIATE FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/101/generators/99_verify_101.sql;

-- Day two
EXECUTE IMMEDIATE FROM @FISERV_SETUP.PUBLIC.WORKSHOP/branches/main/labs/data-intelligence-app/generators/99_verify_setup.sql;
```

If a row says `FAIL`, tell your facilitator which check failed before trying to fix it.

To pick up a correction made during the workshop, re-fetch:

```sql
ALTER GIT REPOSITORY FISERV_SETUP.PUBLIC.WORKSHOP FETCH;
```

## Credits

Day two is adapted from [Build an End-to-End Application Using CoCo on
Snowflake](https://www.snowflake.com/en/developers/guides/sfguide-build-end-to-end-ai-app-on-snowflake/),
re-cut around a payments dataset. Section names match the published guide.

All data is synthetic.
