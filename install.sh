#!/usr/bin/env bash
# install.sh — Install sprint-planner as a global OpenCode skill
#
# Creates a symlink: ~/.config/opencode/skill/sprint-planner → this directory
# Then checks all prerequisites and prints opencode.json configuration snippet.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCODE_SKILLS_DIR="${HOME}/.config/opencode/skill"
TARGET="${OPENCODE_SKILLS_DIR}/sprint-planner"

echo ""
echo "Installing sprint-planner skill..."
echo "  Source : ${SKILL_DIR}"
echo "  Target : ${TARGET}"
echo ""

# ── Ensure skill directory exists ────────────────────────────────────────────
mkdir -p "${OPENCODE_SKILLS_DIR}"

# ── Handle existing target ───────────────────────────────────────────────────
if [[ -e "$TARGET" ]]; then
  if [[ -L "$TARGET" ]]; then
    echo "Removing existing symlink..."
    rm "$TARGET"
  else
    echo "Error: ${TARGET} already exists and is not a symlink." >&2
    echo "Please remove it manually and re-run install.sh." >&2
    exit 1
  fi
fi

# ── Create symlink ────────────────────────────────────────────────────────────
ln -s "${SKILL_DIR}" "${TARGET}"
echo "Symlink created: ${TARGET} -> ${SKILL_DIR}"
echo ""

# ── Prerequisite checks ──────────────────────────────────────────────────────
echo "Checking prerequisites..."
echo ""
missing=()

check_cmd() {
  local cmd="$1"
  local install_hint="${2:-}"
  if command -v "$cmd" &>/dev/null; then
    printf "  %-12s OK\n" "$cmd"
  else
    printf "  %-12s MISSING%s\n" "$cmd" "${install_hint:+  ($install_hint)}"
    missing+=("$cmd")
  fi
}

check_cmd acli       "brew install atlassian-cli or see https://acli.atlassian.com"
check_cmd gh         "brew install gh"
check_cmd jq         "brew install jq"
check_cmd python3    "brew install python3"
check_cmd bc         "brew install bc"

echo ""

# Check pyyaml separately
if python3 -c "import yaml" 2>/dev/null; then
  printf "  %-12s OK\n" "pyyaml"
else
  printf "  %-12s MISSING  (pip3 install pyyaml)\n" "pyyaml"
  missing+=("pyyaml")
fi

echo ""

# ── Auth checks ──────────────────────────────────────────────────────────────
echo "Checking authentication..."
echo ""

acli_ok=true
gh_ok=true

if acli jira workitem view LSH-1 --json &>/dev/null; then
  printf "  %-12s authenticated\n" "acli (Jira)"
else
  printf "  %-12s NOT authenticated  (run: acli auth login)\n" "acli (Jira)"
  acli_ok=false
fi

if gh auth status &>/dev/null; then
  printf "  %-12s authenticated\n" "gh (GitHub)"
else
  printf "  %-12s NOT authenticated  (run: gh auth login)\n" "gh (GitHub)"
  gh_ok=false
fi

echo ""

# ── Result summary ────────────────────────────────────────────────────────────
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Warning: ${#missing[@]} prerequisite(s) missing: ${missing[*]}"
  echo "The skill will still install, but some phases may fail until these are available."
  echo ""
fi

if ! $acli_ok || ! $gh_ok; then
  echo "Warning: One or more CLI tools are not authenticated."
  echo "Authenticate them before running /sprint-planning."
  echo ""
fi

# ── opencode.json snippet ────────────────────────────────────────────────────
echo "Installation complete."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Add the following to ~/.config/opencode/opencode.json:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
cat <<'JSON'
{
  "$schema": "https://opencode.ai/config.json",
  "skills": {
    "paths": ["~/.config/opencode/skill"]
  },
  "command": {
    "sprint-planning": {
      "description": "Run pre-sprint planning workflow for Reporting, Insights & Benchmarks",
      "prompt": "Run the sprint planning workflow using the sprint-planner skill. Follow all 7 phases in order."
    }
  }
}
JSON
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Restart OpenCode after editing opencode.json to load the skill."
echo ""
echo "Then trigger with: /sprint-planning"
echo ""

# ── Zendesk field reminder ────────────────────────────────────────────────────
echo "One-time setup required after install:"
echo ""
echo "  Discover the Zendesk custom field on a known Jira bug:"
echo "    acli jira workitem view <BUG-KEY> --fields '*all' --json \\"
echo "      | jq 'to_entries | map(select(.key | test(\"zendesk|zd\"; \"i\"))) | .[]'"
echo ""
echo "  Record the field ID in references/jira-fields.md"
echo ""
