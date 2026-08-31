# Fiserv European Acquiring — workspace context

You are helping a Fiserv data engineer or analyst work with European card acquiring data in
Snowflake. This file is read automatically, so you already know the domain. Do not ask the
user to re-explain it.

## What the business does

Fiserv acquires card payments for merchants across four European regions. A cardholder taps
or enters a card, the merchant's terminal or gateway sends an **authorisation** to Fiserv,
Fiserv routes it to the card scheme and the issuer, and an approve or decline comes back.
Fiserv then bills the merchant a set of **fee lines** on the approved transactions.

## Database

`FISERV_PAYMENTS_DB`, schemas:

| Schema | Contents |
|---|---|
| `RAW` | Source tables: `MERCHANTS`, `AUTHORISATIONS`, `FEE_LINES`, `PAYMENT_PRODUCTS`, `MERCHANT_FEEDBACK`, `SUPPORT_CASES` |
| `DYNAMIC_TABLES` | Three-tier declarative pipeline |
| `INTERACTIVE` | Interactive tables plus an unclustered standard baseline |
| `SEMANTIC` | Semantic view, Cortex Search services, agent |
| `DBT_STAGING` / `DBT_ANALYTICS` | dbt project output |

Data window is **June to September 2025**. Currency is **EUR only**. If asked about a period
outside that window, say so rather than returning zero.

## Definitions that are easy to get wrong

These are the ones that produce confidently wrong answers, so apply them without being asked.

**Processed volume means APPROVED authorisations only.** `AUTHORISATIONS` contains
`Approved`, `Declined` and `Referred` rows. Declined and referred attempts carry an
`AUTH_AMOUNT` but never settle, so `SUM(AUTH_AMOUNT)` across all rows overstates volume.
Filter to `AUTH_RESULT = 'Approved'`.

**Approval rate is approvals divided by ATTEMPTS.** The denominator is every row in
`AUTHORISATIONS`, not a count from `FEE_LINES`.

**`FEE_LINES` fans out roughly three to one against `AUTHORISATIONS`.** There are about three
fee lines per approved authorisation, and fees exist only on approved authorisations. Never
join the two and then sum an authorisation column: volume and transaction counts will be
roughly tripled. Aggregate each at its own grain and join the aggregates.

**Total fees is not revenue.** `FEE_CATEGORY` splits into `Pass-through` (interchange to the
issuer, scheme fees to the card scheme — Fiserv collects and pays these straight out) and
`Acquirer Revenue` (acquirer margin and gateway fees — Fiserv keeps these). For any question
about revenue, income or margin, sum only `Acquirer Revenue`. Reporting total fees as revenue
overstates it by about 66%.

## Known data quality issues

The data contains real defects. Do not silently work around them, and do not "fix" them
unless asked — surfacing them is often the point.

Expect NULLs in the amount and fee columns. Because `SUM()` over a group where every row is
NULL returns NULL rather than 0, these propagate into aggregates as NULL rows rather than as
zeros. Check for them rather than assuming they are absent, and name the column you found
them in.

## House style

- British English. `authorisation`, not `authorization`.
- Lower case SQL keywords in dbt models, upper case in standalone scripts, matching what is
  already in the file you are editing.
- Explain the grain of any result you produce. State whether a number counts attempts,
  approvals, or fee lines.
- When a query could plausibly hit the fan-out or the pass-through trap, say which one you
  avoided and how.
