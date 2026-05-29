# insights-product-owner-agent

An agentic Product Owner OpenCode skill for the **Reporting, Insights & Benchmarks** team at Lightspeed Hospitality.

Automates pre-sprint planning by scanning the Jira backlog, triaging bugs by Zendesk ticket count, inferring velocity from GitHub PR history, and generating an interactive sprint recommendation — with Jira write-back on confirmation.

---

## What It Does

| Phase | What Happens |
|-------|-------------|
| 1 — Squad Config | Loads team roster and capacity from `squad.yaml`; asks PM about PTO |
| 2 — Velocity Baseline | Analyses last 5 sprints via Jira history + GitHub PR throughput |
| 3 — Backlog Scan | Surfaces new bugs, stale bugs, and feature backlog via JQL |
| 4 — Roadmap Alignment | Checks in-flight epics; prompts PM for strategic priorities |
| 5 — Sprint Recommendation | Ranks bugs by Zendesk count; selects features by roadmap priority; assigns engineers by repo expertise; checks dependencies and DoR |
| 6 — Interactive Confirmation | Three confirmation rounds before writing anything to Jira |
| 7 — Jira Write-back | Assigns confirmed tickets to the active sprint with correct assignees |

---

## Prerequisites

| Tool | Purpose | Install |
|------|---------|---------|
| `acli` | Atlassian CLI for Jira | See [acli docs](https://acli.atlassian.com) |
| `gh` | GitHub CLI | `brew install gh` |
| `jq` | JSON processor | `brew install jq` |
| `python3` | YAML parsing + report formatting | `brew install python3` |
| `pyyaml` | Python YAML library | `pip3 install pyyaml` |
| `bc` | Math for velocity calculation | `brew install bc` |

All CLIs must be authenticated before running the skill.

---

## Installation

### Step 1 — Clone this repo

```bash
git clone https://github.com/ls-stuart-miller/insights-product-owner-agent.git
cd insights-product-owner-agent
```

### Step 2 — Run the installer

```bash
bash install.sh
```

This creates a symlink at `~/.config/opencode/skill/sprint-planner` pointing to this directory, checks prerequisites, and prints the `opencode.json` snippet to add.

### Step 3 — Update `opencode.json`

Add to `~/.config/opencode/opencode.json`:

```json
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
```

### Step 4 — Discover the Zendesk field (one-time)

The native Jira-Zendesk integration field ID varies per instance. Run this once against a known bug ticket that has at least one linked Zendesk ticket:

```bash
acli jira workitem view LSH-XXXX --fields '*all' --json \
  | jq 'to_entries | map(select(.key | test("zendesk|zd"; "i"))) | .[]'
```

Record the field ID in `references/jira-fields.md`.

### Step 5 — Confirm squad config

Review `squad.yaml` and update repository assignments for each engineer. The defaults are reasonable but based on role inference — confirm with your team.

---

## Usage

Restart OpenCode after editing `opencode.json`, then trigger the sprint planner:

```
/sprint-planning
```

Or ask naturally:

> "Plan the sprint for the RIB team"
> "What should we work on this sprint?"
> "Prepare the sprint backlog"

The agent runs all 7 phases and prompts you for confirmation before writing anything to Jira.

---

## Configuration

### `squad.yaml` — Team roster

Edit before each sprint to reflect current availability:

```yaml
members:
  - name: Peter Scardera
    pto_this_sprint: 2   # days off this sprint
```

The agent will also ask about capacity changes at runtime, so editing the file is optional for one-off adjustments.

### Adjusting the bug/feature split

The default allocation is **30% bugs / 70% features**. Mention it during the sprint planning conversation to change it:

> "Let's go 50/50 on bugs and features this sprint"

### Adjusting T-shirt sizing

See `references/sizing-guide.md` for the size → days mapping and classification heuristics. Calibrate the values based on observed sprint data over time.

---

## File Structure

```
insights-product-owner-agent/
├── SKILL.md                      ← OpenCode skill (the orchestration brain)
├── squad.yaml                    ← Team roster and configuration
├── install.sh                    ← Installer / prerequisite checker
├── scripts/
│   ├── velocity.sh               ← GitHub PR throughput analysis
│   ├── backlog-scan.sh           ← Jira JQL queries for bugs + features
│   ├── capacity.sh               ← Sprint capacity calculator
│   └── sprint-report.sh          ← Markdown sprint report formatter
└── references/
    ├── jira-fields.md            ← Jira custom field IDs (update after discovery)
    └── sizing-guide.md           ← T-shirt size heuristics and calibration guide
```

---

## Extending to Other Teams

The skill is fully team-agnostic. To adopt it for another squad:

1. Fork this repo
2. Update `squad.yaml`:
   - Change `jira_team_name` and `jira_team_uuid`
   - Replace the `members` list
   - Update `repos`
3. Find your team UUID: `bash ~/.config/opencode/skill/atlassian-cli-jira/scripts/team-lookup.sh "Your Team Name"`
4. Run `bash install.sh`

---

## Known Limitations

- **Roadmap in Google Slides**: Until your roadmap is fully migrated to Jira Epics, the agent will prompt you manually for top priorities at the start of each run. Once epics are in Jira, Phase 4 becomes fully automated.
- **Zendesk field requires one-time discovery**: The field ID is instance-specific and must be found once (see Step 4 above).
- **Velocity approximation**: When story points are sparse, the model uses GitHub PR throughput as a proxy. Calibrate `references/sizing-guide.md` over time for better accuracy.
- **Sprint must exist in Jira**: The Jira write-back in Phase 7 requires an active sprint to already exist. Ask your team lead to create it before running the planner.

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `acli: command not found` | Install acli: see [acli.atlassian.com](https://acli.atlassian.com) |
| `gh: authentication required` | Run `gh auth login` |
| `No board found for team` | Ask your PM for the Jira board ID and update the SKILL.md config table |
| `pyyaml not found` | Run `pip3 install pyyaml` |
| Zendesk count always 0 | Run field discovery (see Step 4) and update `references/jira-fields.md` |
| Velocity shows 0 PRs | Confirm the GitHub org name (`lightspeed-hospitality`) and that `gh` is authenticated with repo access |
