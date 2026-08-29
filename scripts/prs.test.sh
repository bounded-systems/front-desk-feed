#!/usr/bin/env bash
# Leak-guard and shape pins for prs.sh. No network, no GitHub.
#
#   bash scripts/prs.test.sh
#
# Written as ATTEMPTS TO LEAK, matching the private lane's filter tests: the
# filter claiming default-deny is not evidence. The fixture carries a private
# row whose title AND whose claim_check URL hold a distinctive marker, so a
# regression that publishes either is caught by the same assert.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$here/prs.sh"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok   — $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL — $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want [$3], got [$2])"; fi; }

SECRET="CONFIDENTIAL-BOARD-MARKER-CODENAME-KESTREL"

fixture() {
  cat <<JSON
{
  "generated_at": "2026-08-28T23:00:00Z",
  "project": { "org": "bounded-systems", "number": 2, "title": "Front Desk" },
  "items": [
    { "repo": "bounded-systems/prx", "number": 10, "title": "a public PR",
      "url": "https://github.com/bounded-systems/prx/pull/10", "type": "PullRequest",
      "issue_state": "OPEN", "repo_private": false, "claimed": false,
      "labels": ["dependencies"], "assignees": ["bdelanghe"],
      "claim_check": { "state": "non_compliant", "conclusion": "failure",
                       "url": "https://github.com/bounded-systems/prx/runs/1",
                       "issue_title": "$SECRET-VIA-CLAIM-CHECK" } },
    { "repo": "bounded-systems/site", "number": 20, "title": "another public PR",
      "url": "https://github.com/bounded-systems/site/pull/20", "type": "PullRequest",
      "issue_state": "OPEN", "repo_private": false, "claimed": false,
      "labels": [],
      "claim_check": { "state": "not_measured", "conclusion": null, "url": null } },
    { "repo": "bounded-systems/.github-private", "number": 30, "title": "$SECRET",
      "url": "https://github.com/bounded-systems/.github-private/pull/30", "type": "PullRequest",
      "issue_state": "OPEN", "repo_private": true, "claimed": true, "labels": [],
      "claim_check": { "state": "compliant", "conclusion": "success",
                       "url": "https://github.com/x/$SECRET-PRIVATE-RUN" } },
    { "repo": "bounded-systems/mystery", "number": 40, "title": "$SECRET-UNKNOWN-VIS",
      "url": "https://github.com/bounded-systems/mystery/pull/40", "type": "PullRequest",
      "issue_state": "OPEN", "repo_private": null, "claimed": false, "labels": [] },
    { "repo": "bounded-systems/prx", "number": 50, "title": "a closed PR",
      "url": "https://github.com/bounded-systems/prx/pull/50", "type": "PullRequest",
      "issue_state": "CLOSED", "repo_private": false, "claimed": false, "labels": [] },
    { "repo": "bounded-systems/prx", "number": 60, "title": "an issue",
      "url": "https://github.com/bounded-systems/prx/issues/60", "type": "Issue",
      "issue_state": "OPEN", "repo_private": false, "claimed": false, "labels": [] }
  ]
}
JSON
}

out="$(fixture | bash "$SCRIPT")"

case "$out" in
  *"$SECRET"*) bad "the private marker leaked into the public PR feed" ;;
  *) ok "the private marker appears nowhere in the output" ;;
esac

check "the feed names itself" "$(jq -r '.feed' <<<"$out")" "front-desk-prs-public"
check "only OPEN public PR rows survive" "$(jq -r '.item_count' <<<"$out")" "2"
check "unknown visibility (null) drops — default-deny" \
  "$(jq -r '[.items[] | select(.repo == "bounded-systems/mystery")] | length' <<<"$out")" "0"
check "assignees are not carried" \
  "$(jq -r '.items[0] | has("assignees")' <<<"$out")" "false"

# ── claim_check (#7) ────────────────────────────────────────────────────────
check "the verdict survives for a public row" \
  "$(jq -r '.items[0].claim_check.state' <<<"$out")" "non_compliant"
check "not_measured is carried as its own state, not folded into a failure" \
  "$(jq -r '.items[1].claim_check.state' <<<"$out")" "not_measured"

# THE SHARP ONE. The verdict is allowlisted KEY BY KEY, so an upstream object
# that grows a field naming an issue cannot ride in on a claim_check nobody
# re-read. The blanket marker check above covers it too, but this pins the
# mechanism rather than the fixture.
check "an extra upstream claim_check key does NOT reach the public feed" \
  "$(jq -r '.items[0].claim_check | has("issue_title")' <<<"$out")" "false"
check "claim_check carries exactly the three allowlisted keys" \
  "$(jq -cr '.items[0].claim_check | keys' <<<"$out")" '["conclusion","state","url"]'

# A row the enrichment never reached (no claim_check at all) must still render.
noc="$(fixture | jq 'del(.items[0].claim_check)' | bash "$SCRIPT")"
check "a row with no claim_check degrades to unknown, not null" \
  "$(jq -r '.items[0].claim_check.state' <<<"$noc")" "unknown"

# claim_counts must describe the PUBLISHED rows. scripts/README.md: the delta
# between the snapshot's counts and the filtered ones is itself a private fact,
# so these are recomputed, never carried through. The private row here is
# `compliant`; a leaked total would say 1 with no compliant row in sight.
check "claim_counts covers only published rows" \
  "$(jq -r '.claim_counts.non_compliant' <<<"$out")" "1"
check "claim_counts does NOT count the dropped private row" \
  "$(jq -r '.claim_counts.compliant' <<<"$out")" "0"
check "claim_counts keeps every state key, zeros included" \
  "$(jq -cr '.claim_counts | keys' <<<"$out")" \
  '["compliant","non_compliant","not_measured","pending","unknown"]'

echo
echo "prs.test.sh: $pass ok, $fail failed"
[ "$fail" -eq 0 ]
