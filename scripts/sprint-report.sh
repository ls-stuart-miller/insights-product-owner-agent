#!/usr/bin/env bash
# sprint-report.sh — Format a sprint plan as Markdown for sharing
#
# Usage:
#   sprint-report.sh --sprint-name NAME --start YYYY-MM-DD --end YYYY-MM-DD \
#                    --plan-file PATH
#
# The plan-file is a JSON file the agent writes with the confirmed sprint plan.
# See the expected schema at the bottom of this file.
#
# Output: Markdown formatted sprint summary (stdout)
#
# Requires: python3, jq

set -euo pipefail

SPRINT_NAME=""
START_DATE=""
END_DATE=""
PLAN_FILE=""

# ── Arg parsing ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sprint-name) SPRINT_NAME="$2"; shift 2 ;;
    --start)       START_DATE="$2";  shift 2 ;;
    --end)         END_DATE="$2";    shift 2 ;;
    --plan-file)   PLAN_FILE="$2";   shift 2 ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: sprint-report.sh --sprint-name NAME --start YYYY-MM-DD --end YYYY-MM-DD --plan-file PATH" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$PLAN_FILE" || ! -f "$PLAN_FILE" ]]; then
  echo "Error: --plan-file is required and must point to an existing file." >&2
  echo "The agent should write the confirmed sprint plan to a temp JSON file before calling this script." >&2
  exit 1
fi

# ── Format report ────────────────────────────────────────────────────────────
python3 - "$PLAN_FILE" "$SPRINT_NAME" "$START_DATE" "$END_DATE" <<'PYEOF'
import sys
import json
from datetime import datetime

plan_file   = sys.argv[1]
sprint_name = sys.argv[2] or "Sprint"
start_date  = sys.argv[3]
end_date    = sys.argv[4]

with open(plan_file) as f:
    plan = json.load(f)

bugs         = plan.get("bugs", [])
features     = plan.get("features", [])
epics        = plan.get("epics_in_flight", [])
capacity     = plan.get("capacity", {})
velocity     = plan.get("velocity_baseline", "N/A")
generated_at = datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")

total_avail    = capacity.get("total_assignable_days", 0)
engineers      = capacity.get("engineers", [])
total_assigned = sum(e.get("assigned_days", 0) for e in engineers)
utilisation    = int(total_assigned / total_avail * 100) if total_avail > 0 else 0

lines = []
lines.append(f"## {sprint_name}")
lines.append(f"")
lines.append(f"| | |")
lines.append(f"|---|---|")
lines.append(f"| **Period** | {start_date} → {end_date} |")
lines.append(f"| **Team** | Reporting, Insights & Benchmarks |")
lines.append(f"| **Velocity baseline** | {velocity} |")
lines.append(f"| **Sprint utilisation** | {total_assigned:.1f}d / {total_avail:.1f}d ({utilisation}%) |")
lines.append(f"| **Generated** | {generated_at} |")
lines.append("")

# Epics in flight
if epics:
    lines.append("### Epics In Flight")
    lines.append("")
    lines.append("| Key | Epic | Progress | Status |")
    lines.append("|-----|------|----------|--------|")
    for e in epics:
        key      = e.get("key", "")
        summary  = e.get("summary", "")
        progress = e.get("progress", "")
        status   = e.get("status", "")
        near_done = " ★" if e.get("near_completion", False) else ""
        lines.append(f"| {key} | {summary}{near_done} | {progress} | {status} |")
    lines.append("")

# Bugs
if bugs:
    lines.append(f"### Bugs ({len(bugs)})")
    lines.append("")
    lines.append("| Key | Summary | Zendesk | Age | Assignee | Flag |")
    lines.append("|-----|---------|---------|-----|----------|------|")
    for b in bugs:
        key       = b.get("key", "")
        summary   = b.get("summary", "")
        zd        = b.get("zendesk_count", 0)
        age       = b.get("age_days", "")
        assignee  = b.get("assignee", "")
        flags     = []
        if b.get("is_new"):   flags.append("NEW")
        if b.get("is_stale"): flags.append("STALE ⚠️")
        flag_str = ", ".join(flags)
        zd_icon = f"🎫 {zd}" if zd else "—"
        lines.append(f"| {key} | {summary} | {zd_icon} | {age}d | {assignee} | {flag_str} |")
    lines.append("")

# Feature work
if features:
    lines.append(f"### Feature Work ({len(features)})")
    lines.append("")
    lines.append("| Key | Summary | Size | Days | Epic | Assignee | Notes |")
    lines.append("|-----|---------|------|------|------|----------|-------|")
    for ft in features:
        key      = ft.get("key", "")
        summary  = ft.get("summary", "")
        size     = ft.get("size", "")
        days     = ft.get("days", "")
        epic     = ft.get("epic", "")
        assignee = ft.get("assignee", "")
        notes    = ft.get("notes", "")
        if ft.get("size_inferred"): notes = f"size inferred{'; ' + notes if notes else ''}"
        lines.append(f"| {key} | {summary} | {size} | {days}d | {epic} | {assignee} | {notes} |")
    lines.append("")

# Capacity summary
if engineers:
    lines.append("### Capacity")
    lines.append("")
    lines.append("| Engineer | Role | Available | Assigned | Utilisation |")
    lines.append("|----------|------|-----------|----------|-------------|")
    for e in engineers:
        name     = e.get("name", "")
        role     = e.get("role", "")
        avail    = e.get("assignable_days", 0)
        assigned = e.get("assigned_days", 0)
        util     = f"{int(assigned / avail * 100)}%" if avail > 0 else "N/A"
        tl_note  = " (TL)" if e.get("is_team_lead") else ""
        buffer   = e.get("team_lead_buffer_days", 0)
        notes    = f"+{buffer}d TL buffer" if buffer else ""
        lines.append(f"| {name}{tl_note} | {role} | {avail}d | {assigned}d | {util} |")
        if notes:
            lines[-1] = lines[-1].rstrip(" |") + f" — {notes} |"
    lines.append("")
    lines.append(f"**Total:** {total_assigned:.1f}d assigned / {total_avail:.1f}d available ({utilisation}% utilised)")
    lines.append("")

# DoR flags
dor_flags = plan.get("dor_flags", [])
if dor_flags:
    lines.append("### Definition of Ready Flags")
    lines.append("")
    lines.append("_These tickets have open DoR issues — resolve before sprint starts:_")
    lines.append("")
    for flag in dor_flags:
        lines.append(f"- **{flag.get('key')}**: {flag.get('issue')}")
    lines.append("")

# Design flags
design_flags = plan.get("design_flags", [])
if design_flags:
    lines.append("### Design Input Required")
    lines.append("")
    lines.append("_These tickets need a design spec before development begins:_")
    lines.append("")
    for flag in design_flags:
        lines.append(f"- **{flag.get('key')}**: {flag.get('summary')}")
    lines.append("")

print("\n".join(lines))
PYEOF

# ──────────────────────────────────────────────────────────────────────────────
# Expected plan-file JSON schema:
# {
#   "velocity_baseline": "~X small, Y medium, Z large per sprint",
#   "bugs": [
#     {
#       "key": "LSH-111",
#       "summary": "Bug description",
#       "zendesk_count": 14,
#       "age_days": 18,
#       "assignee": "Nick Nassar",
#       "is_new": true,
#       "is_stale": false
#     }
#   ],
#   "features": [
#     {
#       "key": "LSH-501",
#       "summary": "Feature description",
#       "size": "M",
#       "days": 1.5,
#       "size_inferred": true,
#       "epic": "LSH-XXX",
#       "assignee": "Nick Nassar",
#       "notes": ""
#     }
#   ],
#   "epics_in_flight": [
#     {
#       "key": "LSH-XXX",
#       "summary": "Epic name",
#       "progress": "45% (9/20)",
#       "status": "In Progress",
#       "near_completion": false
#     }
#   ],
#   "capacity": {
#     "total_assignable_days": 40.0,
#     "engineers": [
#       {
#         "name": "Peter Scardera",
#         "role": "Senior Backend Engineer",
#         "is_team_lead": true,
#         "assignable_days": 5.4,
#         "assigned_days": 5.0,
#         "team_lead_buffer_days": 1.4
#       }
#     ]
#   },
#   "dor_flags": [
#     { "key": "LSH-505", "issue": "Missing acceptance criteria" }
#   ],
#   "design_flags": [
#     { "key": "LSH-506", "summary": "New dashboard view" }
#   ]
# }
