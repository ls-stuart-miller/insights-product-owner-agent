# T-Shirt Sizing Guide

Used by the sprint planner to estimate capacity for tickets that lack story points.
The agent applies these heuristics when reading a ticket's summary and description.

---

## Size → Days Mapping

| Size | Days | GitHub PR Proxy                              | Description                                              |
|------|------|----------------------------------------------|----------------------------------------------------------|
| XS   | 0.25 | <50 lines, 1–2 files                         | Trivial — config tweak, copy change, one-liner fix       |
| S    | 0.5  | <100 lines, <5 files                         | Small bug fix or minor addition to existing feature      |
| M    | 1.5  | 100–400 lines, <15 files                     | Standard feature work, moderate backend or UI change     |
| L    | 3.0  | 400–1000 lines, <40 files                    | Complex feature, multi-service change, new endpoint set  |
| XL   | 5.0  | >1000 lines or >40 files                     | Large refactor, new service, migration, greenfield work  |

---

## Classification Heuristics

When the agent infers size from a ticket description, it applies the following:

### API / Backend Scope

| Signal                                              | Base Size |
|-----------------------------------------------------|-----------|
| No API change — pure logic/config tweak             | XS–S      |
| Modify existing endpoint (add/change field)         | S–M       |
| New endpoint on existing service                    | M         |
| 2+ new endpoints or complex aggregation             | L         |
| New service, new DB table, or service integration   | XL        |

### Frontend Scope

| Signal                                              | Base Size |
|-----------------------------------------------------|-----------|
| Text/style/copy change                              | XS–S      |
| Modify existing component                           | S–M       |
| New component, standalone                           | M         |
| New page or view                                    | L         |
| New feature with multiple views + state management  | XL        |

### Size Bumps (apply on top of base)

| Condition                                           | Adjustment |
|-----------------------------------------------------|------------|
| Any DB migration or schema change                   | +1 size    |
| Breaking API change requiring consumer updates      | +1 size    |
| Third-party integration (new external API)          | +1 size    |
| Cross-service data flow change                      | +0.5 size  |
| Requires E2E test coverage                          | +0.5 day   |
| No existing tests to build on (greenfield)          | +0.5 day   |
| Requires architecture sign-off (Todd)               | Flag as L+ |

### Quick-reject signals (likely XL or needs splitting)

- Ticket description uses "refactor the entire X"
- Ticket affects more than 3 repos
- Ticket has been deferred 3+ sprints (may be underspecified)
- Acceptance criteria have more than 7 bullet points

---

## Calibration

Adjust the **Days** column based on observed sprint data.

The `velocity.sh` script correlates merged PR sizes with elapsed time, which
provides an empirical calibration signal over time. After 3–4 sprints of
operation, compare inferred estimates to actual merge times and update this
file accordingly.

---

## Presentation to PM

When surfacing inferred sizes, always flag them clearly:

```
[LSH-501] Feature name  | M (inferred) | → Nick
```

The PM can challenge any inferred size during Round 3 of the confirmation
dialogue. The agent should update days and recompute the capacity summary
before final confirmation.
