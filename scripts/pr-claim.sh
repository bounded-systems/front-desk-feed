#!/usr/bin/env bash
# Enrich a Front Desk snapshot's PUBLIC open PR rows with the verdict of the
# `pr-claim` check — the gate `.github-private`#723 put on every PR (#7).
#
#   bash pr-claim.sh          < front-desk.json > enriched.json   # needs GITHUB_TOKEN
#   bash pr-claim.sh join     < {snapshot, claim_checks}          # pure, testable
#
# WHY THIS PUBLISHES A VERDICT AND NOT AN ANSWER OF ITS OWN
# ---------------------------------------------------------
# `prs.sh` has carried `claimed: .claimed` since it was written, and for a PULL
# REQUEST row that is the `claimed` label or an assignee ON THE PR. The claim
# convention never writes a claim onto a PR — both doors write onto an ISSUE —
# so that field is 0 by construction and prs.bounded.tools has been rendering a
# number that cannot be non-zero as though it were measured.
#
# The question the page means to ask is "does this PR name an issue that is
# claimed", and `pr-claim` already answers it. This reads that answer.
#
# It does NOT resolve linked issues and decide for itself. Two reasons, and the
# second is the one that matters here:
#
#   1. It would be a third implementation of one predicate, next to
#      `_pr-claim.yml` and `.github-private`'s projection. scripts/README.md
#      accepts duplication in this repo for a stated reason and bounds the
#      damage; a THIRD copy that also had an opinion is not covered by that
#      bound.
#   2. Resolving an issue means READING an issue — its title, its labels — and
#      this lane must never hold issue text it has no business publishing.
#      Reading a check run touches no issue at all, so no issue title, number or
#      claimant CAN reach the feed. That is safe by construction rather than by
#      review, which is the only kind of safe this repo accepts.
#
# PUBLIC ROWS ONLY. The snapshot carries private repos' rows; there is no reason
# to fetch a private repo's check runs from a lane whose whole job is publishing
# the public half. Restricting the enrichment to rows the snapshot positively
# established as `repo_private == false` means the private half is never even
# requested — the same default-deny direction public.sh and prs.sh already take.
#
# THE CHECK IS NOT NAMED `pr-claim`. A job that calls a reusable workflow reports
# as `<caller job> / <reusable job>`, so it is `claim / pr-claim` in
# `.github-private` and `pr-claim / pr-claim` in `.github`. Matching the bare
# name would find NOTHING anywhere and report the whole org as un-adopted — a
# clean-looking run asserting the opposite of the truth. Match the suffix.
set -euo pipefail

# Pure join. Kept separate so the shape rules are pinned with no network, the
# same split project.sh/public.sh already use.
join() {
  jq '
    ((.claim_checks // []) | map({ (.key): . }) | add // {}) as $checks
    | .snapshot
    | .items = [
        .items[]
        | if (.type == "PullRequest" and .issue_state == "OPEN"
               and .repo_private == false and .repo != null)
          then . + { claim_check:
                       ($checks["\(.repo)#\(.number)"]
                        # A qualifying row we could not reach is `unknown`, NEVER
                        # `not_measured`. The latter positively asserts that the
                        # repo has not adopted the check, and .github-private#725
                        # uses that count as its rollout metric — reading "could
                        # not look" as "nothing was there" would invent coverage.
                        // { state: "unknown", conclusion: null, url: null })
                       | { state, conclusion, url } }
          else . end
      ]
  '
}

if [ "${1:-}" = "join" ]; then
  join
  exit 0
fi

: "${GITHUB_TOKEN:?GITHUB_TOKEN is required to read check runs}"
API="${GITHUB_API_URL:-https://api.github.com}"

snapshot="$(mktemp)"
checks="$(mktemp)"
runs_out="$(mktemp)"
trap 'rm -f "$snapshot" "$checks" "$runs_out"' EXIT
cat > "$snapshot"
echo '[]' > "$checks"

fetch() {
  curl -fsS \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$1"
}

# CAPPED. Two reads per PR against a token with an hourly budget; a dependency-bot
# surge must degrade visibly into `unknown` rather than exhaust the budget and
# take the whole feed with it.
BUDGET="${PR_CLAIM_BUDGET:-300}"
attempted=0

while IFS=$'\t' read -r repo number; do
  [ -n "${number:-}" ] || continue
  [ "$attempted" -lt "$BUDGET" ] || break
  attempted=$((attempted + 1))

  # BEST-EFFORT PER ROW, never fatal. A row this token cannot reach is an
  # expected outcome, not a broken lane — and unlike the parity asserts in
  # publish.yml, nothing here decides whether the feed is COMPLETE. It only
  # decides how much is known about a row already in it.
  sha="$(fetch "$API/repos/$repo/pulls/$number" 2>/dev/null | jq -r '.head.sha // empty')" || sha=""
  [ -n "$sha" ] || continue
  fetch "$API/repos/$repo/commits/$sha/check-runs?per_page=100" > "$runs_out" 2>/dev/null || continue
  [ -s "$runs_out" ] || continue

  jq -c --arg repo "$repo" --arg number "$number" '
    [ .check_runs[]?
      | select(.name == "pr-claim" or (.name | endswith(" / pr-claim"))) ]
    | sort_by(.started_at // "") | last
    | if . == null then
        # No such check on this head: the repo has not adopted `pr-claim`.
        { state: "not_measured", conclusion: null, url: null }
      elif (.status // "") != "completed" then
        { state: "pending", conclusion: null, url: .html_url }
      else
        { state: (if .conclusion == "success" then "compliant"
                  elif (["failure","timed_out","action_required","cancelled"]
                        | index(.conclusion)) != null then "non_compliant"
                  # neutral / skipped / stale, and whatever GitHub adds later.
                  # `pr-claim` carries no `if:` and cannot legitimately skip, so
                  # an unrecognised conclusion is a fact about the platform — not
                  # evidence to report as a finding against the author.
                  else "unknown" end),
          conclusion: .conclusion, url: .html_url }
      end
    | . + { key: ($repo + "#" + $number) }' "$runs_out" >> "$checks.jsonl" || true
done < <(jq -r '.items[]
                | select(.type == "PullRequest" and .issue_state == "OPEN"
                         and .repo_private == false and .repo != null)
                | "\(.repo)\t\(.number)"' "$snapshot")

if [ -s "${checks}.jsonl" ]; then
  jq -s '.' "$checks.jsonl" > "$checks"
  rm -f "$checks.jsonl"
fi

jq -n --slurpfile snapshot "$snapshot" --slurpfile claim_checks "$checks" \
  '{ snapshot: $snapshot[0], claim_checks: $claim_checks[0] }' \
  | join
