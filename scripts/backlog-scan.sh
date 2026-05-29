#!/usr/bin/env bash
# backlog-scan.sh — Scan Jira backlog for bugs and feature tickets
#
# Usage:
#   backlog-scan.sh --team-uuid UUID --project LSH [--zendesk-field cf[XXXXX]] [--limit N]
#
# Output:
#   JSON with keys: new_bugs, stale_bugs, all_open_bugs, feature_backlog
#
# Requires: acli (Atlassian CLI, authenticated), jq

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
TEAM_UUID="857e08e4-972a-4190-af30-e215a842ffba"
PROJECT="LSH"
ZENDESK_FIELD=""   # e.g. "cf[10100]" — leave empty if not yet discovered
LIMIT=50

# ── Arg parsing ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --team-uuid)      TEAM_UUID="$2";      shift 2 ;;
    --project)        PROJECT="$2";        shift 2 ;;
    --zendesk-field)  ZENDESK_FIELD="$2";  shift 2 ;;
    --limit)          LIMIT="$2";          shift 2 ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: backlog-scan.sh --team-uuid UUID --project LSH [--zendesk-field cf[XXXXX]]" >&2
      exit 1
      ;;
  esac
done

# ── Helpers ──────────────────────────────────────────────────────────────────
run_jql() {
  local label="$1"
  local jql="$2"
  echo "  Running: ${label}..." >&2

  local result
  result=$(acli jira workitem search "$jql" --limit "$LIMIT" --json 2>/dev/null || echo "[]")

  # Validate output is JSON array
  if ! echo "$result" | jq -e 'if type == "array" then true else false end' >/dev/null 2>&1; then
    echo "  Warning: unexpected response for ${label}, defaulting to []" >&2
    echo "[]"
    return
  fi

  echo "$result"
}

# ── JQL Queries ──────────────────────────────────────────────────────────────

# New bugs: created in last 14 days, not yet resolved
NEW_BUGS_JQL="project = ${PROJECT} \
  AND issuetype = Bug \
  AND team = '${TEAM_UUID}' \
  AND status not in (Done, Closed, Resolved) \
  AND created >= -14d \
  ORDER BY created DESC"

# Stale bugs: open >30 days, not updated in 30+ days — candidate for triage
STALE_BUGS_JQL="project = ${PROJECT} \
  AND issuetype = Bug \
  AND team = '${TEAM_UUID}' \
  AND status not in (Done, Closed, Resolved) \
  AND created <= -30d \
  AND updated <= -30d \
  ORDER BY created ASC"

# All open bugs: used for Zendesk cross-referencing + ranked triage list
ALL_BUGS_JQL="project = ${PROJECT} \
  AND issuetype = Bug \
  AND team = '${TEAM_UUID}' \
  AND status not in (Done, Closed, Resolved) \
  ORDER BY created DESC"

# Feature backlog: stories and tasks in Backlog / To Do status
FEATURES_JQL="project = ${PROJECT} \
  AND issuetype in (Story, Task) \
  AND team = '${TEAM_UUID}' \
  AND status in (Backlog, 'To Do', Open) \
  ORDER BY priority ASC, created ASC"

# ── Run scans ────────────────────────────────────────────────────────────────
echo "Starting backlog scan for team UUID: ${TEAM_UUID}" >&2
echo "" >&2

NEW_BUGS=$(run_jql "new_bugs"       "$NEW_BUGS_JQL")
STALE_BUGS=$(run_jql "stale_bugs"   "$STALE_BUGS_JQL")
ALL_BUGS=$(run_jql "all_open_bugs"  "$ALL_BUGS_JQL")
FEATURES=$(run_jql "feature_backlog" "$FEATURES_JQL")

echo "" >&2
echo "Scan complete." >&2

# ── Zendesk enrichment note ──────────────────────────────────────────────────
# If --zendesk-field is provided, each ticket's Zendesk count can be read from
# the custom field. The agent should sort all_open_bugs by this field after
# receiving this output. If not provided, sort by age only and flag the gap.

ZENDESK_NOTE=""
if [[ -z "$ZENDESK_FIELD" ]]; then
  ZENDESK_NOTE="Zendesk field not configured. Run field discovery (see references/jira-fields.md) to enable Zendesk-based bug prioritisation. Falling back to age-based sort."
else
  ZENDESK_NOTE="Zendesk field: ${ZENDESK_FIELD}. Sort all_open_bugs by this field descending for customer-impact ranking."
fi

# ── Output JSON ──────────────────────────────────────────────────────────────
jq -n \
  --argjson new_bugs      "$NEW_BUGS" \
  --argjson stale_bugs    "$STALE_BUGS" \
  --argjson all_open_bugs "$ALL_BUGS" \
  --argjson feature_backlog "$FEATURES" \
  --arg zendesk_note      "$ZENDESK_NOTE" \
  --arg zendesk_field     "$ZENDESK_FIELD" \
  --arg scanned_at        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{
    meta: {
      scanned_at: $scanned_at,
      zendesk_field: $zendesk_field,
      zendesk_note: $zendesk_note
    },
    counts: {
      new_bugs:        ($new_bugs | length),
      stale_bugs:      ($stale_bugs | length),
      all_open_bugs:   ($all_open_bugs | length),
      feature_backlog: ($feature_backlog | length)
    },
    new_bugs:        $new_bugs,
    stale_bugs:      $stale_bugs,
    all_open_bugs:   $all_open_bugs,
    feature_backlog: $feature_backlog
  }'
