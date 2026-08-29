#!/usr/bin/env bash
# Shape pins for pr-claim.sh's pure join. No network, no GitHub.
#
#   bash scripts/pr-claim.test.sh
#
# The load-bearing pin is the DIRECTION of the default: a qualifying row with no
# verdict must be `unknown`, never `not_measured`. `not_measured` positively
# asserts that a repo has not adopted `pr-claim`, and .github-private#725 uses
# that count as its rollout metric — so reading "could not look" as "nothing was
# there" would invent coverage that was never measured.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$here/pr-claim.sh"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok   — $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL — $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want [$3], got [$2])"; fi; }

fixture() {
  cat <<'JSON'
{
  "snapshot": {
    "generated_at": "2026-08-28T23:00:00Z",
    "items": [
      { "repo": "bounded-systems/prx", "number": 10, "type": "PullRequest",
        "issue_state": "OPEN", "repo_private": false },
      { "repo": "bounded-systems/site", "number": 20, "type": "PullRequest",
        "issue_state": "OPEN", "repo_private": false },
      { "repo": "bounded-systems/.github-private", "number": 30, "type": "PullRequest",
        "issue_state": "OPEN", "repo_private": true },
      { "repo": "bounded-systems/prx", "number": 40, "type": "PullRequest",
        "issue_state": "CLOSED", "repo_private": false },
      { "repo": "bounded-systems/prx", "number": 50, "type": "Issue",
        "issue_state": "OPEN", "repo_private": false }
    ]
  },
  "claim_checks": [
    { "key": "bounded-systems/prx#10", "state": "compliant",
      "conclusion": "success", "url": "https://github.com/x/1" }
  ]
}
JSON
}

out="$(fixture | bash "$SCRIPT" join)"

check "the snapshot is returned, not the wrapper" \
  "$(jq -r '.generated_at' <<<"$out")" "2026-08-28T23:00:00Z"
check "a verdict joins onto its row by repo#number" \
  "$(jq -r '.items[0].claim_check.state' <<<"$out")" "compliant"
check "the raw conclusion is carried for audit" \
  "$(jq -r '.items[0].claim_check.conclusion' <<<"$out")" "success"

# THE DIRECTION PIN.
check "a qualifying row with NO verdict is unknown, not not_measured" \
  "$(jq -r '.items[1].claim_check.state' <<<"$out")" "unknown"

# Rows the enrichment must not touch at all. A private row gaining a
# claim_check would mean this lane had fetched a private repo's check runs —
# the request it is written never to make.
check "a PRIVATE row is left untouched" \
  "$(jq -r '.items[2] | has("claim_check")' <<<"$out")" "false"
check "a CLOSED PR is left untouched" \
  "$(jq -r '.items[3] | has("claim_check")' <<<"$out")" "false"
check "an ISSUE row is left untouched" \
  "$(jq -r '.items[4] | has("claim_check")' <<<"$out")" "false"

check "row count is unchanged by the join" \
  "$(jq -r '.items | length' <<<"$out")" "5"

# An upstream verdict object carrying an extra key must be reduced here too —
# the filter allowlists as well, but a field that never enters cannot leak.
extra="$(fixture | jq '.claim_checks[0].issue_title = "LEAK"' | bash "$SCRIPT" join)"
check "an extra key on the verdict does not survive the join" \
  "$(jq -r '.items[0].claim_check | has("issue_title")' <<<"$extra")" "false"

# No claim_checks at all — the lane could not reach anything.
none="$(fixture | jq '.claim_checks = []' | bash "$SCRIPT" join)"
check "with no verdicts, every qualifying row is unknown" \
  "$(jq -r '[.items[] | select(has("claim_check")) | .claim_check.state] | unique | join(",")' <<<"$none")" \
  "unknown"

echo
echo "pr-claim.test.sh: $pass ok, $fail failed"
[ "$fail" -eq 0 ]
