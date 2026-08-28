-- Fiserv Snowcamp Workshop: run the agent evaluation.
--
-- Reshapes AGENT_EVAL_SET into the two columns the evaluation framework requires
-- (input query VARCHAR, ground truth VARIANT) and starts a run.
--
-- ROW ACCESS POLICY CAVEAT, verified rather than assumed. The docs state under Known
-- limitations that you cannot evaluate an agent whose queries depend on session
-- attributes or variables, "including agents that use those values with a row access
-- policy". ACQUIRING_REGION_POLICY is keyed on CURRENT_ROLE(), not on a session
-- variable, and this evaluation runs as ACCOUNTADMIN, for which the policy predicate
-- returns TRUE for every row. So the agent sees the same full dataset the ground truth
-- was derived from. If the run is ever executed as SOUTHERN_EUROPE_MANAGER the numeric
-- answers will legitimately not match and the failures will be the policy, not the agent.
--
-- PARSE_JSON is required: OBJECT_CONSTRUCT returns OBJECT, not VARIANT.
--
-- ground_truth_invocations is not optional in practice. Supplying only
-- ground_truth_output made tool_selection_accuracy score 0.0 on all seven questions,
-- because TSA divides matched tools by max(expected, actual) and an empty expected
-- list can never match. That reads as total agent failure when nothing is wrong.

USE ROLE ACCOUNTADMIN;
USE DATABASE FISERV_PAYMENTS_DB;
USE SCHEMA SEMANTIC;

CREATE OR REPLACE TABLE AGENT_EVAL_INPUT (
    INPUT_QUERY  VARCHAR,
    GROUND_TRUTH VARIANT
);

INSERT INTO AGENT_EVAL_INPUT (INPUT_QUERY, GROUND_TRUTH)
WITH tools AS (
    -- A correlated subquery over FLATTEN is rejected ("unsupported subquery type"),
    -- so the tool list is aggregated separately and joined back.
    SELECT s.QUESTION_ID,
           ARRAY_AGG(OBJECT_CONSTRUCT('tool_name', TRIM(t.value::VARCHAR))) AS invocations
    FROM AGENT_EVAL_SET s,
         LATERAL SPLIT_TO_TABLE(s.EXPECTED_TOOLS, ',') t
    GROUP BY s.QUESTION_ID
)
SELECT
    s.QUESTION,
    PARSE_JSON(OBJECT_CONSTRUCT(
        'ground_truth_output',
        s.EXPECTED_ANSWER
          || ' The response must not make this mistake: ' || s.TRAP,
        'ground_truth_invocations', t.invocations
    )::VARCHAR)
FROM AGENT_EVAL_SET s
JOIN tools t ON t.QUESTION_ID = s.QUESTION_ID;

SELECT COUNT(*) AS rows_loaded,
       COUNT_IF(GROUND_TRUTH:ground_truth_output IS NOT NULL) AS with_answer,
       COUNT_IF(ARRAY_SIZE(GROUND_TRUTH:ground_truth_invocations) > 0) AS with_tools
FROM AGENT_EVAL_INPUT;
