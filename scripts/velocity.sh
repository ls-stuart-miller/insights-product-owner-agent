#!/usr/bin/env bash
# velocity.sh — Analyze GitHub PR throughput for sprint velocity estimation
#
# Usage:
#   velocity.sh --org ORG --repos "r1,r2,r3" --from YYYY-MM-DD --to YYYY-MM-DD
#
# Output:
#   JSON object with PR counts by size bucket and estimated engineer-days
#
# Requires: gh (GitHub CLI, authenticated), jq
#
# Size classification (lines changed + file count + review rounds):
#   small  : <150 weighted lines, <6 files   → ~0.5 days
#   medium : <500 weighted lines, <20 files  → ~1.5 days
#   large  : <1200 weighted lines, <50 files → ~3.0 days
#   xl     : anything bigger                 → ~5.0 days

set -euo pipefail

# ── Defaults ────────────────────────────────────────────────────────────────
ORG="lightspeed-hospitality"
REPOS=""
FROM_DATE=""
TO_DATE=""

# ── Arg parsing ─────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --org)   ORG="$2";       shift 2 ;;
    --repos) REPOS="$2";     shift 2 ;;
    --from)  FROM_DATE="$2"; shift 2 ;;
    --to)    TO_DATE="$2";   shift 2 ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: velocity.sh --repos \"r1,r2\" --from YYYY-MM-DD --to YYYY-MM-DD" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$REPOS" || -z "$FROM_DATE" || -z "$TO_DATE" ]]; then
  echo "Error: --repos, --from, and --to are required." >&2
  exit 1
fi

# ── Size classification ──────────────────────────────────────────────────────
# Each review round adds ~50 lines of weighted complexity.
classify_pr() {
  local additions="$1"
  local deletions="$2"
  local changed_files="$3"
  local review_count="$4"

  local raw_lines=$(( additions + deletions ))
  local weighted=$(( raw_lines + (review_count * 50) ))

  if   [[ $weighted -lt 150  && $changed_files -lt 6  ]]; then echo "small"
  elif [[ $weighted -lt 500  && $changed_files -lt 20 ]]; then echo "medium"
  elif [[ $weighted -lt 1200 && $changed_files -lt 50 ]]; then echo "large"
  else echo "xl"
  fi
}

# ── Size → days mapping ──────────────────────────────────────────────────────
days_for_size() {
  case "$1" in
    small)  echo "0.5" ;;
    medium) echo "1.5" ;;
    large)  echo "3.0" ;;
    xl)     echo "5.0" ;;
    *)      echo "0"   ;;
  esac
}

# ── Main ─────────────────────────────────────────────────────────────────────
total_small=0
total_medium=0
total_large=0
total_xl=0
total_prs=0
total_days="0"
backend_prs=0
frontend_prs=0

BACKEND_REPOS=("insights-service" "open-search-service" "automated-reporting-service")
FRONTEND_REPOS=("lighthouse-insights" "hospitality-platform")

is_backend() {
  local r="$1"
  for br in "${BACKEND_REPOS[@]}"; do [[ "$r" == "$br" ]] && return 0; done
  return 1
}

IFS=',' read -ra REPO_LIST <<< "$REPOS"
for repo in "${REPO_LIST[@]}"; do
  repo="${repo// /}"  # trim spaces

  echo "  Fetching PRs: ${ORG}/${repo} merged:${FROM_DATE}..${TO_DATE}" >&2

  # GitHub search qualifier for merged date range
  pr_data=$(gh pr list \
    --repo "${ORG}/${repo}" \
    --state merged \
    --search "merged:${FROM_DATE}..${TO_DATE}" \
    --json number,additions,deletions,changedFiles,reviews \
    --limit 200 2>/dev/null || echo "[]")

  if [[ "$pr_data" == "[]" || -z "$pr_data" ]]; then
    echo "  No PRs found for ${repo} in this period." >&2
    continue
  fi

  pr_count=$(echo "$pr_data" | jq 'length')
  echo "  Found ${pr_count} PRs in ${repo}" >&2

  while IFS= read -r pr; do
    additions=$(echo "$pr" | jq -r '.additions // 0')
    deletions=$(echo "$pr" | jq -r '.deletions // 0')
    changed_files=$(echo "$pr" | jq -r '.changedFiles // 0')
    review_count=$(echo "$pr" | jq -r '.reviews | length // 0')

    size=$(classify_pr "$additions" "$deletions" "$changed_files" "$review_count")
    days=$(days_for_size "$size")

    case "$size" in
      small)  (( total_small++  )) ;;
      medium) (( total_medium++ )) ;;
      large)  (( total_large++  )) ;;
      xl)     (( total_xl++     )) ;;
    esac

    (( total_prs++ ))
    total_days=$(echo "$total_days + $days" | bc)

    if is_backend "$repo"; then
      (( backend_prs++ ))
    else
      (( frontend_prs++ ))
    fi
  done < <(echo "$pr_data" | jq -c '.[]')
done

# ── Output JSON ──────────────────────────────────────────────────────────────
backend_pct=0
frontend_pct=0
if [[ $total_prs -gt 0 ]]; then
  backend_pct=$(echo "scale=0; $backend_prs * 100 / $total_prs" | bc)
  frontend_pct=$(( 100 - backend_pct ))
fi

cat <<EOF
{
  "period": {
    "from": "${FROM_DATE}",
    "to":   "${TO_DATE}"
  },
  "total_prs": ${total_prs},
  "by_size": {
    "small":  ${total_small},
    "medium": ${total_medium},
    "large":  ${total_large},
    "xl":     ${total_xl}
  },
  "estimated_engineer_days": ${total_days},
  "split": {
    "backend_prs":   ${backend_prs},
    "frontend_prs":  ${frontend_prs},
    "backend_pct":   ${backend_pct},
    "frontend_pct":  ${frontend_pct}
  }
}
EOF
