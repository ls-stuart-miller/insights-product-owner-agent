#!/usr/bin/env bash
# capacity.sh — Calculate sprint capacity from squad.yaml
#
# Modes:
#   Default   : Parse squad.yaml, return capacity breakdown per active engineer
#   --estimate: Return estimated days for a T-shirt size (no YAML needed)
#
# Usage:
#   capacity.sh [--squad-file PATH] [--pto "Alice:2,Bob:1"]
#   capacity.sh --estimate --size S|M|L|XL
#
# Output: JSON capacity breakdown
#
# Requires: python3, pyyaml (pip3 install pyyaml)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQUAD_FILE="${SCRIPT_DIR}/../squad.yaml"
PTO_OVERRIDES=""
ESTIMATE_MODE=false
SIZE=""

# ── Arg parsing ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --squad-file) SQUAD_FILE="$2"; shift 2 ;;
    --pto)        PTO_OVERRIDES="$2"; shift 2 ;;
    --estimate)   ESTIMATE_MODE=true; shift ;;
    --size)       SIZE="$2"; shift 2 ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: capacity.sh [--squad-file PATH] [--pto \"Name:days\"]" >&2
      echo "       capacity.sh --estimate --size S|M|L|XL" >&2
      exit 1
      ;;
  esac
done

# ── Estimate mode: T-shirt size → days ──────────────────────────────────────
if $ESTIMATE_MODE; then
  if [[ -z "$SIZE" ]]; then
    echo '{"error": "Provide --size S, M, L, or XL with --estimate"}' >&2
    exit 1
  fi
  case "${SIZE^^}" in
    XS) echo '{"size":"XS","days":0.25,"description":"Trivial — config, copy, one-liner"}' ;;
    S)  echo '{"size":"S", "days":0.5, "description":"Small bug fix or minor addition"}' ;;
    M)  echo '{"size":"M", "days":1.5, "description":"Standard feature work"}' ;;
    L)  echo '{"size":"L", "days":3.0, "description":"Complex feature, multi-service change"}' ;;
    XL) echo '{"size":"XL","days":5.0, "description":"Large refactor, new service, migration"}' ;;
    *)
      echo "{\"error\": \"Unknown size '${SIZE}'. Use XS, S, M, L, or XL\"}" >&2
      exit 1
      ;;
  esac
  exit 0
fi

# ── Capacity calculation mode ────────────────────────────────────────────────
if [[ ! -f "$SQUAD_FILE" ]]; then
  echo "{\"error\": \"squad.yaml not found at: ${SQUAD_FILE}\"}" >&2
  exit 1
fi

# Check for pyyaml
if ! python3 -c "import yaml" 2>/dev/null; then
  echo "{\"error\": \"pyyaml not installed. Run: pip3 install pyyaml\"}" >&2
  exit 1
fi

python3 - "$SQUAD_FILE" "$PTO_OVERRIDES" <<'PYEOF'
import sys
import json

try:
    import yaml
except ImportError:
    print(json.dumps({"error": "pyyaml not installed. Run: pip3 install pyyaml"}))
    sys.exit(1)

squad_file = sys.argv[1]
pto_raw = sys.argv[2] if len(sys.argv) > 2 else ""

# Parse PTO overrides: "Alice:2,Bob:1"
pto_map: dict[str, float] = {}
if pto_raw:
    for entry in pto_raw.split(","):
        entry = entry.strip()
        if ":" in entry:
            name, days = entry.split(":", 1)
            pto_map[name.strip().lower()] = float(days)

with open(squad_file) as f:
    config = yaml.safe_load(f)

squad = config.get("squad", {})
members = config.get("members", [])

overhead_pct: float = squad.get("ceremony_overhead_pct", 15) / 100
sprint_days: int = squad.get("sprint_cadence_days", 14)

# Roles excluded from dev sprint capacity
NON_DEV_ROLES = {"Product Manager", "Senior Designer"}

engineers = []
total_available = 0.0

for m in members:
    role = m.get("role", "")
    name = m.get("name", "")

    # Skip non-devs and anyone with 0 capacity (Architect tracks separately)
    if role in NON_DEV_ROLES:
        continue
    if m.get("capacity_days_per_sprint", 0) == 0:
        continue

    base_capacity: float = float(m.get("capacity_days_per_sprint", 8))
    pto: float = pto_map.get(name.lower(), float(m.get("pto_this_sprint", 0)))

    # Net available: subtract PTO, then apply ceremony overhead
    net = (base_capacity - pto) * (1 - overhead_pct)
    net = round(net, 1)

    # No additional TL buffer — Peter's capacity_days_per_sprint already
    # reflects his management load (2–3d vs the standard 8d for ICs).
    net_assignable = net
    team_lead_buffer = 0.0

    total_available += net_assignable

    engineers.append({
        "name": name,
        "jira_user": m.get("jira_user", ""),
        "github_handle": m.get("github_handle", ""),
        "role": role,
        "is_team_lead": m.get("is_team_lead", False),
        "primary_repos": m.get("primary_repos", []),
        "secondary_repos": m.get("secondary_repos", []),
        "base_capacity_days": base_capacity,
        "pto_days": pto,
        "available_days": net,
        "team_lead_buffer_days": team_lead_buffer,
        "assignable_days": net_assignable,
        "assigned_days": 0.0,   # filled in by the agent as tickets are allocated
    })

output = {
    "sprint_cadence_days": sprint_days,
    "ceremony_overhead_pct": int(squad.get("ceremony_overhead_pct", 15)),
    "total_assignable_days": round(total_available, 1),
    "engineers": engineers,
}

print(json.dumps(output, indent=2))
PYEOF
