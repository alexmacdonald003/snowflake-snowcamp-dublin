#!/usr/bin/env python3
"""
Interactive Tables concurrency load test.

WHY THIS EXISTS
---------------
A single point lookup does NOT demonstrate Interactive Tables. Measured on this dataset,
one lookup against the standard table was 198ms elapsed / 37ms execution, and the
interactive table was 289ms elapsed / 26ms execution. Interactive wins on execution time
and loses on elapsed, because a single query is dominated by round-trip overhead. If the
session-4 module is built around one lookup it will look like the feature does nothing, or
worse.

The claim worth testing is concurrency: many simultaneous point lookups, where an
interactive warehouse should hold latency flat while a standard warehouse queues.

WHY execute_async
-----------------
An earlier attempt ran 30 parallel `snow sql` processes. That measured CLI startup, not
Snowflake: 4.8s vs 4.0s, which is noise. It also made 30 separate sessions, so
INFORMATION_SCHEMA.QUERY_HISTORY (session-scoped) could only ever see one query each and
reported a single row per warehouse.

execute_async submits without blocking, so N queries are in flight on the warehouse at
once, and they all share ONE session, which means QUERY_HISTORY can actually see them and
report per-query execution and queue times.

Runs unchanged in a Snowsight notebook (uses the active session) or locally.
"""

import argparse
import statistics
import sys
import time
from concurrent.futures import ThreadPoolExecutor

DB = "FISERV_PAYMENTS_DB"
SCHEMA = "INTERACTIVE"


def get_connection(connection_name):
    """Active Snowsight session if present, otherwise a named local connection.

    In a Snowsight notebook the session already exists and connection_name is
    ignored, which is why --connection is not unconditionally required.

    Running locally there is no session to inherit, so a connection name is
    mandatory. It must name a connection already defined in your Snowflake CLI
    config (~/.snowflake/connections.toml), NOT an account identifier or a URL.
    List what you have with:  snow connection list
    """
    try:
        from snowflake.snowpark.context import get_active_session
        return get_active_session().connection, "snowsight"
    except Exception:
        pass

    if not connection_name:
        sys.exit(
            "error: no active Snowsight session, so --connection is required.\n"
            "\n"
            "Pass the name of a connection from your Snowflake CLI config:\n"
            "    python3 interactive_concurrency_test.py --connection MY_CONNECTION\n"
            "\n"
            "List the connections you already have with:\n"
            "    snow connection list\n"
            "\n"
            "The connection's role needs USAGE on FISERV_WH and\n"
            "FISERV_INTERACTIVE_WH, and SELECT on FISERV_PAYMENTS_DB.INTERACTIVE.\n"
            "Alternatively, paste this script into a Snowsight notebook cell and\n"
            "run it there, where the session is supplied for you and no\n"
            "--connection argument is needed."
        )

    import snowflake.connector
    return snowflake.connector.connect(connection_name=connection_name), "local"


def sample_auth_ids(conn, n):
    cur = conn.cursor()
    cur.execute(f"USE WAREHOUSE FISERV_WH")
    cur.execute(
        f"SELECT AUTH_ID FROM {DB}.{SCHEMA}.AUTH_LOOKUP SAMPLE ({n * 4} ROWS) LIMIT {n}"
    )
    return [r[0] for r in cur.fetchall()]


def run_batch(conn, table, warehouse, auth_ids, submit_threads=16):
    """Submit one point lookup per auth_id concurrently, wait for all, return query ids."""
    setup = conn.cursor()
    setup.execute(f"USE WAREHOUSE {warehouse}")

    query_ids = []

    def submit(auth_id):
        cur = conn.cursor()
        cur.execute_async(
            f"SELECT AUTH_ID, AUTH_AMOUNT, MERCHANT_ID, AUTH_RESULT "
            f"FROM {DB}.{SCHEMA}.{table} WHERE AUTH_ID = '{auth_id}'"
        )
        return cur.sfqid

    started = time.time()
    with ThreadPoolExecutor(max_workers=submit_threads) as pool:
        query_ids = list(pool.map(submit, auth_ids))

    # Block until every query has finished before stopping the clock.
    for qid in query_ids:
        while conn.is_still_running(conn.get_query_status(qid)):
            time.sleep(0.02)
    wall = time.time() - started

    return query_ids, wall


def server_side_stats(conn, query_ids):
    """Per-query execution and queue time, straight from Snowflake rather than the client.

    Runs on FISERV_WH deliberately. Interactive warehouses enforce a low
    STATEMENT_TIMEOUT_IN_SECONDS (5s on this account), and scanning QUERY_HISTORY exceeds
    it, so reading the results on the interactive warehouse fails with error 000630.
    Interactive warehouses are for point lookups, not for analytical scans.
    """
    id_list = ",".join(f"'{q}'" for q in query_ids)
    cur = conn.cursor()
    cur.execute("USE WAREHOUSE FISERV_WH")
    cur.execute(
        f"""
        SELECT EXECUTION_TIME, QUEUED_OVERLOAD_TIME, TOTAL_ELAPSED_TIME
        FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY(RESULT_LIMIT => 10000))
        WHERE QUERY_ID IN ({id_list})
        """
    )
    rows = cur.fetchall()
    if not rows:
        return None
    execs = sorted(r[0] for r in rows)
    queued = [r[1] for r in rows]
    return {
        "queries_seen": len(rows),
        "exec_p50": statistics.median(execs),
        "exec_p95": execs[int(len(execs) * 0.95) - 1] if len(execs) > 1 else execs[0],
        "exec_max": max(execs),
        "queued_total": sum(queued),
        "queued_max": max(queued),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--queries", type=int, default=200,
                    help="Concurrent point lookups per variant. Default 200. "
                         "The contrast between the two warehouse types widens as "
                         "this rises; below about 50 it is not visible.")
    ap.add_argument("--threads", type=int, default=16,
                    help="Threads used to SUBMIT the queries. Default 16. This "
                         "is client-side submission concurrency, not Snowflake "
                         "concurrency, so raising it does not increase load.")
    ap.add_argument("--connection", default=None,
                    help="Name of a connection in your Snowflake CLI config "
                         "(~/.snowflake/connections.toml), e.g. MY_DEMO_ACCOUNT. "
                         "Required when running locally. Not needed, and "
                         "ignored, inside a Snowsight notebook. "
                         "Run 'snow connection list' to see yours.")
    args = ap.parse_args()

    conn, mode = get_connection(args.connection)
    print(f"connected ({mode}); {args.queries} concurrent point lookups, "
          f"{args.threads} submit threads\n")

    auth_ids = sample_auth_ids(conn, args.queries)
    if len(auth_ids) < args.queries:
        print(f"warning: only sampled {len(auth_ids)} ids")

    variants = [
        ("STD_AUTH_LOOKUP", "FISERV_WH", "standard table, standard warehouse"),
        ("AUTH_LOOKUP", "FISERV_INTERACTIVE_WH", "interactive table, interactive warehouse"),
    ]

    results = {}
    for table, wh, label in variants:
        # Warm up so neither variant pays for warehouse resume in the measured run.
        run_batch(conn, table, wh, auth_ids[:5], submit_threads=5)

        qids, wall = run_batch(conn, table, wh, auth_ids, args.threads)
        stats = server_side_stats(conn, qids)
        results[table] = (wall, stats, label)

        qps = len(auth_ids) / wall
        print(f"{label}")
        print(f"  wall clock      {wall:7.2f} s   ({qps:6.1f} queries/sec)")
        if stats:
            print(f"  queries seen    {stats['queries_seen']}")
            print(f"  exec p50        {stats['exec_p50']:7.0f} ms")
            print(f"  exec p95        {stats['exec_p95']:7.0f} ms")
            print(f"  exec max        {stats['exec_max']:7.0f} ms")
            print(f"  queued total    {stats['queued_total']:7.0f} ms "
                  f"(max {stats['queued_max']:.0f} ms)")
        else:
            print("  no server-side stats returned")
        print()

    std_wall, std_stats, _ = results["STD_AUTH_LOOKUP"]
    int_wall, int_stats, _ = results["AUTH_LOOKUP"]

    # Judge on SERVER-SIDE latency and queueing, not on wall clock.
    #
    # Wall clock in this harness is client-bound: submission runs through a fixed thread
    # pool on a single connection and completion is polled every 20ms, so both variants
    # land within about 10% of each other no matter how fast Snowflake is. Reporting that
    # as the headline would understate the feature by a factor of twenty.
    #
    # Execution time and queue time come from QUERY_HISTORY and are what actually differ.
    print("=" * 68)
    if std_stats and int_stats:
        lat = std_stats["exec_p50"] / int_stats["exec_p50"] if int_stats["exec_p50"] else float("nan")
        print(f"Execution p50:   {std_stats['exec_p50']:.0f} ms standard "
              f"vs {int_stats['exec_p50']:.0f} ms interactive  ->  {lat:.1f}x faster")
        print(f"Execution p95:   {std_stats['exec_p95']:.0f} ms standard "
              f"vs {int_stats['exec_p95']:.0f} ms interactive")
        print(f"Queue time:      {std_stats['queued_total']:.0f} ms standard "
              f"vs {int_stats['queued_total']:.0f} ms interactive")
        print()
        if int_stats["queued_total"] == 0 and std_stats["queued_total"] > 1000:
            print("The interactive warehouse absorbed the concurrency with NO queueing,")
            print("while the standard warehouse queued. That is the point of the feature.")
        elif lat < 2:
            print("Latency difference is small at this concurrency. Raise --queries.")
    print()
    print(f"Wall clock was {std_wall:.1f}s vs {int_wall:.1f}s, but IGNORE THAT: this")
    print("harness is client-bound on submission and polling, not on Snowflake. Quote the")
    print("execution and queue figures above instead.")


if __name__ == "__main__":
    sys.exit(main())
