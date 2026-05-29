# Jira Custom Field Reference

This file records discovered Jira custom field names and IDs for the LSH project.
**Update this file after running first-time field discovery** — the backlog scan
script uses these values to enable Zendesk-based bug prioritisation.

---

## How to Discover Custom Fields

Run this against any known bug ticket that has at least one linked Zendesk ticket:

```bash
acli jira workitem view LSH-XXXX --fields '*all' --json \
  | jq 'to_entries | map(select(.key | test("zendesk|zd|support"; "i"))) | .[]'
```

If that returns nothing, scan all custom fields:

```bash
acli jira workitem view LSH-XXXX --fields '*all' --json \
  | jq 'to_entries | map(select(.key | startswith("cf"))) | .[] | {key, value}' \
  | head -60
```

Look for a field with a numeric count value that corresponds to linked Zendesk tickets.

---

## Known Fields

| Field Name          | Field ID            | Description                               | Discovered |
|---------------------|---------------------|-------------------------------------------|------------|
| Team                | `customfield_10001` | Team UUID assignment                      | Confirmed  |
| Sprint              | `customfield_10020` | Active sprint                             | Confirmed  |
| Story Points        | `customfield_10016` | Story point estimate (standard field)     | Confirmed  |
| Zendesk Ticket Count | **TBD**            | Count of linked Zendesk support tickets   | Not yet    |

---

## How to Use the Zendesk Field

Once discovered, update `scripts/backlog-scan.sh` line:

```bash
ZENDESK_FIELD=""   # e.g. "cf[10100]" — leave empty if not yet discovered
```

Change to:

```bash
ZENDESK_FIELD="cf[XXXXX]"   # your discovered field ID
```

Or pass it at runtime:

```bash
bash scripts/backlog-scan.sh --team-uuid "857e08e4-..." --zendesk-field "cf[10100]"
```

---

## Notes

- Field IDs vary per Jira Cloud instance — there is no universal value.
- The Zendesk-Jira native integration typically creates a field visible as
  "Zendesk Tickets" in the Jira UI sidebar.
- If the count isn't a direct field but a count of issue links of type
  "Zendesk", the agent can count `.fields.issuelinks` entries with
  `type.name == "Zendesk"` as a fallback.
