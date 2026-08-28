#!/usr/bin/env python3
"""
Turn a day-2 guide sheet into a Snowflake Notebook spec of markdown and SQL cells.

WHY THIS EXISTS
---------------
The markdown sheets under guide/ are the source of truth. Attendees read them as
notebooks in Snowsight because that needs no printing, no external tool and no
second login. Hand-copying content into a notebook would create two copies that
drift apart, and the sheet is what gets corrected during rehearsal.

So the notebook is GENERATED from the sheet. Edit the .md, re-run this, redeploy.

WHY SQL BECOMES A CELL RATHER THAN A CODE BLOCK
-----------------------------------------------
The official quickstart this mirrors gives every step two paths: a CoCo prompt and a
copyable SQL block. In a notebook the SQL block can be better than a copy button: it
becomes a cell you run in place. Prose and prompts stay markdown; each fenced ```sql
block becomes a runnable SQL cell directly beneath the prompt it implements.

CELL SPLITTING
--------------
Sections split on `## ` headings, which gives one section per lab step. That is the
unit an attendee works through and the unit a facilitator calls out ("everyone on
Data Quality now"). Within a section, prose and SQL alternate in document order, so
the prompt always appears above the SQL that implements it.

USAGE
    python3 prompt_sheet_to_notebook.py <sheet.md> <out_spec.json>
"""

import json
import re
import sys

# Matches a fenced SQL block, capturing its body. Non-greedy so consecutive blocks
# in one section stay separate cells rather than collapsing into one.
SQL_FENCE = re.compile(r"```sql\s*\n(.*?)\n```", re.DOTALL)


def slug(text, fallback):
    """Derive a SQL-safe cell result name from a heading."""
    s = re.sub(r"[^0-9a-zA-Z]+", "_", (text or "").strip().lower()).strip("_")
    s = re.sub(r"^[0-9_]+", "", s)  # result names cannot start with a digit
    return (s[:40] or fallback)


def split_sections(markdown_text):
    """Split on level-2 headings, keeping each heading with its body.

    Text before the first `## ` is the title and preamble, returned first so it
    becomes the notebook's opening cell.
    """
    sections, current = [], []
    for line in markdown_text.split("\n"):
        if line.startswith("## "):
            if current:
                sections.append("\n".join(current).strip())
            current = [line]
        else:
            current.append(line)
    if current:
        sections.append("\n".join(current).strip())

    # Drop the trailing horizontal rules that separated steps in the flat document.
    # They are noise once each step is its own cell.
    cleaned = []
    for section in sections:
        section = re.sub(r"\n---\s*$", "", section).strip()
        if section:
            cleaned.append(section)
    return cleaned


def section_to_cells(section, index):
    """Split one section into alternating markdown and SQL cells, in document order."""
    heading = section.split("\n", 1)[0].lstrip("# ").strip()
    base = slug(heading, f"step_{index}")

    cells = []
    cursor = 0
    sql_seq = 0

    for match in SQL_FENCE.finditer(section):
        prose = section[cursor:match.start()].strip()
        if prose:
            cells.append({"type": "markdown", "source": prose})

        sql_seq += 1
        # Unique per cell, and readable in the notebook's variable list so a later
        # Python cell could consume it if we ever add charts.
        name = base if sql_seq == 1 else f"{base}_{sql_seq}"
        cells.append({"type": "sql", "name": name, "source": match.group(1).strip()})
        cursor = match.end()

    tail = section[cursor:].strip()
    if tail:
        cells.append({"type": "markdown", "source": tail})

    return cells


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)

    sheet_path, spec_path = sys.argv[1], sys.argv[2]

    with open(sheet_path, encoding="utf-8") as f:
        sections = split_sections(f.read())

    # Attendees look for a Run button first. Without this note the notebook reads as
    # broken, and without the two-paths explanation they will not know the prompt and
    # the SQL beneath it do the same job.
    how_to_use = (
        "> **How to use this notebook.** Every step gives you two paths that reach the "
        "same result.\n>\n"
        "> **Prompt CoCo** - open the **Cortex Code** panel in this workspace and type "
        "the quoted text. CoCo writes the SQL, runs it, and shows the result. Read what "
        "it proposes before you accept it: deciding whether the answer is right is the "
        "skill this session teaches.\n>\n"
        "> **Run the SQL cell** - the cell underneath does the same job directly. Use it "
        "if you want precise control, or to catch up if you fall behind.\n>\n"
        "> Work through the cells in order."
    )

    cells = [{"type": "markdown", "source": sections[0]},
             {"type": "markdown", "source": how_to_use}]
    for i, section in enumerate(sections[1:], start=1):
        cells.extend(section_to_cells(section, i))

    with open(spec_path, "w", encoding="utf-8") as f:
        json.dump({"cells": cells}, f, indent=2, ensure_ascii=False)

    counts = {}
    for c in cells:
        counts[c["type"]] = counts.get(c["type"], 0) + 1
    print(f"{sheet_path} -> {spec_path}: {len(cells)} cells {counts}")


if __name__ == "__main__":
    main()
