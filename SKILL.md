---
name: sprint-planner
description: >
  Agentic Product Owner for sprint planning for the Reporting, Insights &
  Benchmarks (RIB) team. Scans Jira backlog for new and stale bugs, triages
  by Zendesk ticket count, infers velocity from GitHub PR history, surfaces
  in-flight epics, and produces an interactive sprint recommendation with
  assignees. On confirmation, writes back to Jira. Use when asked to
  "plan the sprint", "prepare sprint backlog", "what should we work on this
  sprint", or when /sprint-planning is invoked.
---

# Sprint Planner — Reporting, Insights & Benchmarks

This skill orchestrates a full pre-sprint analysis and produces an interactive,
confirmed sprint backlog recommendation. All phases run in order. The PM is
prompted for input at key decision points. **Nothing is written to Jira until
the PM gives explicit final confirmation.**

---

## Prerequisites

Verify all of these are installed and authenticated before proceeding:

```bash
acli jira workitem view LSH-1 --json          # should return ticket data
gh auth status                                 # should show authenticated user
jq --version                                   # JSON processor
python3 -c "import yaml; print('ok')"          # PyYAML installed
bc --version                                   # math for velocity calc
```

If any prerequisite is missing, tell the PM and stop. Do not proceed with
partial tooling.

---

## Key Configuration

| Item             | Value                                      |
|------------------|--------------------------------------------|
| Jira Project     | `LSH`                                      |
| Team Name        | `Reporting, Insights & Benchmarks (HOS)`   |
| Team UUID        | `857e08e4-972a-4190-af30-e215a842ffba`     |
| GitHub Org       | `lightspeed-hospitality`                   |
| Squad Config     | `squad.yaml` (in this skill's directory)   |
| Sprint Cadence   | 14 days                                    |
| Velocity Lookback| Last 5 completed sprints                   |

## Repos

| Repo                        | Domain                                      |
|-----------------------------|---------------------------------------------|
| `insights-service`          | Backend — Insights data service             |
| `lighthouse-insights`       | Frontend — current Reports UI               |
| `open-search-service`       | Backend — search and query layer            |
| `automated-reporting-service` | Backend — automated report generation    |
| `hospitality-platform`      | Frontend — platform-wide component migration target |

---

## Full Workflow

Run all 7 phases in sequence. Show the PM a phase header before each one so
they can follow along. Example: `"### Phase 2 of 7 — Velocity Baseline"`.

---

### Phase 1 — Load Squad Config & Capacity

Read `squad.yaml` from this skill's base directory.

Extract for use throughout:
- All members where `capacity_days_per_sprint > 0` — these are your **active engineers**
- Each engineer's `primary_repos` and `secondary_repos`
- Each engineer's `capacity_days_per_sprint` minus `pto_this_sprint`
- The `ceremony_overhead_pct` for capacity deduction

Then ask the PM:

> "Before I start the backlog scan — any capacity changes this sprint I should
> know about? (PTO, hiring loops, on-call rotations, team events)"

Update in-memory capacity values based on their response. **Do not write to
`squad.yaml`** unless they explicitly ask you to persist changes.

**Team Lead note:** Peter Scardera is the team lead (`is_team_lead: true`).
Automatically reserve 20% of his available days for code review and unplanned
support. Reduce his assignable capacity by that amount before planning.

---

### Phase 2 — Velocity Baseline

**Step 2a: Find the active Jira board for this team**

```bash
acli jira board list --project LSH --json \
  | jq '.[] | select(.name | test("Reporting|Insights|Benchmarks|RIB"; "i")) | {id, name}'
```

If no board matches, search more broadly:
```bash
acli jira board list --project LSH --json | jq '[.[] | {id, name}]'
```

Ask the PM to confirm the correct board ID if ambiguous. Store it as
`BOARD_ID` for the rest of the workflow.

**Step 2b: Retrieve last 5 closed sprints**

```bash
acli jira sprint list --board $BOARD_ID --state closed --limit 5 --json
```

Extract `name`, `startDate`, and `endDate` for each sprint. If dates are
missing on old sprints, calculate from cadence (14-day windows working back
from the most recent).

**Step 2c: Analyze GitHub PR throughput per sprint**

For each of the 5 sprints, call:

```bash
bash scripts/velocity.sh \
  --org lightspeed-hospitality \
  --repos "insights-service,lighthouse-insights,open-search-service,automated-reporting-service" \
  --from "SPRINT_START" \
  --to "SPRINT_END"
```

Aggregate results across all 5 sprints to produce a throughput baseline:
- Average PRs per sprint by size bucket: `small / medium / large / xl`
- Translate to days using T-shirt sizing (see `references/sizing-guide.md`)
- Note backend vs. frontend split

**Step 2d: Story point fallback**

Check if the most recent completed sprint had story points on >50% of tickets:

```bash
acli jira workitem search \
  "project = LSH AND team = '857e08e4-972a-4190-af30-e215a842ffba' AND sprint in closedSprints() AND sprint = '$LAST_SPRINT_NAME'" \
  --json --limit 100 \
  | jq '[.[] | select(.fields.story_points != null)] | length'
```

If story points are well-tracked (>50% coverage), use average story point
velocity instead of PR throughput. Otherwise, use PR throughput model.

**Output to PM:**

```
Velocity baseline (last 5 sprints):
  ~X small, Y medium, Z large, W XL tickets per sprint
  ≈ N total engineer-days of throughput per sprint
  (Backend: A% | Frontend: B%)
```

---

### Phase 3 — Backlog Scan

Run the full backlog scan script:

```bash
bash scripts/backlog-scan.sh \
  --team-uuid "857e08e4-972a-4190-af30-e215a842ffba" \
  --project LSH
```

This outputs JSON with four categories:
1. `new_bugs` — bugs created in the last 14 days
2. `stale_bugs` — bugs open >30 days, not updated in >30 days
3. `all_open_bugs` — all open bugs, for Zendesk cross-reference
4. `feature_backlog` — To Do / Backlog stories and tasks

**Zendesk field discovery (first time only):**

If `references/jira-fields.md` shows the Zendesk field as "TBD", run:

```bash
acli jira workitem view <any-open-bug-key> --fields '*all' --json \
  | jq 'to_entries | map(select(.key | test("zendesk|zd|support"; "i"))) | .[]'
```

Record the field ID in `references/jira-fields.md` and pass it to the
backlog scan script via `--zendesk-field cf[XXXXX]`.

**After the scan, surface a summary to the PM:**

```
Backlog scan complete:
  New bugs (last 14 days): N
  Stale bugs (open >30 days): N
  Total open bugs: N
  Feature backlog items: N
```

---

### Phase 4 — Roadmap Alignment

**Step 4a: Check for active epics in Jira**

```bash
acli jira workitem search \
  "project = LSH AND issuetype = Epic AND team = '857e08e4-972a-4190-af30-e215a842ffba' AND status not in (Done, Closed)" \
  --json --limit 20
```

For each epic found, calculate progress:

```bash
# Count total and done child tickets for epic LSH-XXX
acli jira workitem search \
  "project = LSH AND parent = LSH-XXX AND status = Done" --count
acli jira workitem search \
  "project = LSH AND parent = LSH-XXX" --count
```

Display epic status table:

```
EPICS IN FLIGHT:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[LSH-XXX] Epic Name                  — 45% (9/20 done)
[LSH-YYY] Epic Name                  — 12% (2/17 done)  ← just started
[LSH-ZZZ] Epic Name                  — 88% (7/8 done)   ← near completion
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Prompt the PM:

> "Any epics you want to defer or descope this sprint? Near-completion epics
> (>75%) are worth prioritising to clear them. Newly started epics (<20%)
> may be candidates to pause if capacity is tight."

**Step 4b: Roadmap transition prompt**

If fewer than 3 active epics are found in Jira, the roadmap may not yet be
fully migrated. Prompt:

> "I only found [N] active epics in Jira. Your roadmap may still be partially
> in Google Slides. Please list your top 3–5 priorities for this sprint
> (epic keys, initiative names, or theme descriptions — anything works):"

Store the response as `roadmap_priorities` (list of strings/keys).

---

### Phase 5 — Sprint Recommendation

Now build the full sprint recommendation using velocity and capacity from
Phases 1–4.

**Step 5a: Compute available capacity**

```bash
bash scripts/capacity.sh --squad-file squad.yaml
```

Apply any PTO adjustments confirmed in Phase 1 via `--pto "Name:days,Name:days"`.

This gives you `available_days` per active engineer. Subtract Peter's 20%
team lead buffer before allocating work.

**Step 5b: Rank and select bugs**

Sort all open bugs by:
1. Zendesk ticket count — descending (most customer-impacted first)
2. Age — oldest first as a tiebreaker
3. Newly created bugs (last 14 days) — apply a soft +1 priority bump

Default rule: **bugs should fill at most 30% of total sprint capacity**.
Flag this threshold to the PM and let them adjust (e.g. if there's a high-
severity incident backlog, they may want 50%).

Match each selected bug to an engineer based on the component or repo label
on the Jira ticket. Use `primary_repos` first, then `secondary_repos`.

**Step 5c: Rank and select feature work**

Fill remaining capacity (~70%) with feature work, prioritised as:
1. Tickets that are children of near-completion epics (>75% done) — clear them
2. Tickets matching `roadmap_priorities` from Phase 4
3. Tickets linked to other in-flight epics
4. Highest-priority items in the general backlog (oldest first)

For any feature ticket without story points, estimate size:
- Read the ticket's summary and description
- Apply heuristics from `references/sizing-guide.md`
- Use `bash scripts/capacity.sh --estimate --size M` to get days
- Flag the estimate as "inferred" so the PM can challenge it

**Step 5d: Assign engineers**

For each ticket:
1. Match to engineers with the relevant `primary_repos` first
2. Track running `assigned_days` per engineer — do not exceed `available_days`
3. If primary-repo engineers are at capacity, try `secondary_repos`
4. If still no match, flag the ticket as "needs assignment" for PM input

**Step 5e: Definition of Ready check**

For each proposed ticket, verify it has:
- A non-empty summary
- A description OR acceptance criteria
- A component, label, or parent epic (for routing)

If a ticket fails DoR, flag it:

> "LSH-XXXX is missing acceptance criteria. Would you like me to draft them
> based on the ticket title, or defer this ticket to a later sprint?"

If the PM asks you to draft ACs, do so inline before including the ticket
in the sprint plan.

**Step 5f: Dependency check**

For all proposed tickets, check blocking links:

```bash
acli jira workitem view <KEY> --fields '*all' --json \
  | jq '.fields.issuelinks[] | select(.type.name == "Blocks") | {outward: .outwardIssue.key}'
```

If ticket A is blocked by ticket B and B is not in the sprint plan, surface:

> "LSH-XXXX is blocked by LSH-YYYY which is not in this sprint. Options:
> (a) Add LSH-YYYY to the sprint, (b) remove LSH-XXXX, or (c) confirm the
> block is already resolved."

---

### Phase 6 — Interactive Confirmation

Present the sprint plan in **three confirmation rounds**. Do not write to
Jira until all rounds pass.

---

**Round 1 — Epics & Strategic Priorities**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SPRINT PRIORITIES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Continuing epics:
  [LSH-XXX] Epic Name              — 88% complete  ★ nearly done
  [LSH-YYY] Epic Name              — 45% complete
  [LSH-ZZZ] Epic Name              — 12% complete

Roadmap priorities confirmed:
  • [stated priority 1]
  • [stated priority 2]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Ask: *"Any epics to defer or descope? Any priorities to add or remove?"*

---

**Round 2 — Bug Triage**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
BUGS PROPOSED FOR THIS SPRINT  (30% of capacity)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [LSH-111] Bug summary here        | 🎫 14 Zendesk | 18d old  | → Nick
  [LSH-222] Bug summary here        | 🎫  8 Zendesk |  3d old  | → Sori    [NEW]
  [LSH-333] Bug summary here        | 🎫  3 Zendesk | 47d old  | → Anthony [STALE ⚠️]

  Stale bugs NOT proposed (0 Zendesk tickets, >60 days):
  [LSH-444] Stale bug summary       | 🎫  0 Zendesk | 71d old  | Consider closing?
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Ask:
> "Confirm these bugs for the sprint? Remove any, add others, or adjust the
> 30% bug allocation? Also — should I mark LSH-444 as Won't Fix or defer
> for another sprint?"

---

**Round 3 — Feature Work & Final Capacity**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FEATURE WORK PROPOSED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [LSH-501] Feature summary         | M (inferred) | → Nick      | Epic: LSH-XXX
  [LSH-502] Feature summary         | L            | → Peter     | Epic: LSH-YYY
  [LSH-503] Feature summary         | S            | → Sori      | Epic: LSH-XXX
  [LSH-504] Feature summary         | M (inferred) | → Sebastien | Tech debt
  [LSH-505] Feature summary         | L            | → Divyang   | Epic: LSH-ZZZ

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CAPACITY SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Peter      6.0d available | 5.5d assigned  (+ 1.5d TL buffer)
  Nick       6.8d available | 6.5d assigned
  Anthony    6.8d available | 6.0d assigned
  Sebastien  6.8d available | 6.0d assigned
  Sori       6.8d available | 6.5d assigned
  Divyang    6.8d available | 6.0d assigned
  ─────────────────────────────────────────
  Total     40.0d available | 36.5d assigned  (91%)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Ask:
> "Does this sprint plan look right? Any tickets to swap, remove, or add?
> Note: items marked '(inferred)' have estimated sizes — correct any that
> look off."

After the PM confirms, ask one final question:

> "Apply this plan to Jira? I'll assign all confirmed tickets to the active
> sprint and set assignees. (yes / no)"

---

### Phase 7 — Jira Write-back

**Only run this phase after the PM types "yes" or equivalent confirmation.**

**Step 7a: Get the active sprint ID**

```bash
acli jira sprint list --board $BOARD_ID --state active --limit 1 --json \
  | jq '.[0].id'
```

**Step 7b: For each confirmed ticket, assign to sprint and set assignee**

```bash
# Move to active sprint (sprint field = customfield_10020)
acli jira workitem edit --key <KEY> --custom-field customfield_10020:<SPRINT_ID>

# Set assignee
acli jira workitem assign --key <KEY> --assignee <jira_user> --yes
```

Repeat for all bugs and features in the confirmed plan.

**Step 7c: Handle stale bug decisions**

If the PM asked to close stale bugs as Won't Fix:

```bash
# Use the transition script from atlassian-cli-jira skill if available,
# or transition directly:
acli jira workitem transition --key <KEY> --status "Closed"
acli jira workitem edit --key <KEY> --custom-field resolution:"Won't Fix"
```

**Step 7d: Output sprint summary**

Generate the final sprint summary:

```bash
bash scripts/sprint-report.sh \
  --sprint-name "$SPRINT_NAME" \
  --start "$SPRINT_START" \
  --end "$SPRINT_END" \
  --plan-file /tmp/sprint-plan.json
```

Output the Markdown result for the PM to copy into Slack, Confluence, or
their sprint planning doc.

---

## Stale Bug Escalation Rules

Apply these rules when surfacing stale bugs in Round 2:

| Age       | Zendesk Count | Recommendation                             |
|-----------|---------------|--------------------------------------------|
| >90 days  | 0             | Recommend closing as Won't Fix             |
| >60 days  | 0             | Flag with ⚠️, ask PM to defer or close    |
| >30 days  | >0            | Include in sprint — customer pain is real  |
| >30 days  | 0             | List below main bug table, PM decides      |
| Any age   | >10           | Escalate — treat as high priority          |

---

## Design & Architect Integration

**Anurag (Designer):** For any feature ticket that:
- Has no Figma link, attached design, or "design done" label
- Is sized M or larger
- Touches a user-facing view or flow

Flag it:
> "LSH-XXXX appears to require design input but has no design spec attached.
> Flag this for Anurag before committing to the sprint?"

**Todd (Architect):** For any ticket sized L or XL, or any ticket that
involves schema changes, new service endpoints, or cross-service data flows:
> "LSH-XXXX is a large/complex ticket. Recommend a quick architecture check
> with Todd before committing to this sprint?"

---

## Notes & Edge Cases

- **No story points + sparse PR data:** Fall back to raw ticket count as
  a proxy. Warn the PM that velocity is approximate and suggest a buffer sprint.
- **Sprint not yet created in Jira:** Ask PM to create the sprint in Jira
  first, then re-run Phase 7.
- **Ticket already in a sprint:** Skip the sprint assignment step for that
  ticket; only update the assignee.
- **Engineer on leave for full sprint:** Remove them from capacity entirely
  and redistribute their proposed tickets. Ask PM to confirm redistribution.
- **Zendesk field not yet discovered:** Skip Zendesk ranking; sort bugs by
  age only. Remind PM to run field discovery (see `references/jira-fields.md`).
- **Roadmap fully in Jira:** Once epics are consistently tracked, Phase 4
  Step 4b (manual priority prompt) can be skipped. The epic query alone
  is sufficient for roadmap alignment.
