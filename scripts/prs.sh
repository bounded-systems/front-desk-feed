#!/usr/bin/env bash
# Filter a Front Desk projection down to the OPEN PULL REQUESTS that may be
# published — the feed prs.bounded.tools serves (.github-private#713).
#
#   bash prs.sh < front-desk.json > front-desk-prs.json
#
# WHY FROM THE SAME SNAPSHOT. public.sh stopped carrying PR rows on the
# maintainer's 2026-08-27 direction (.github-private#480): the desk is a queue
# of claimable work and a PR is not claimable work. But "what is open" is still
# a question worth one page, so the PR rows get their own feed — derived from
# the SAME /tmp/front-desk.json in the same run as the desk feed, so the two
# can never disagree about what the board said at a moment. A second query
# would be a second board.
#
# SAME DEFAULT-DENY AS public.sh, same fail direction: a row survives only when
# the snapshot positively established `repo_private == false`; true and null
# both drop, because "too little published" is the only acceptable failure
# mode for a public surface. OPEN only — a merged or closed PR is history, and
# the board carries thousands of those.
#
# FIELDS ARE ALLOWLISTED. `assignees` is not carried (same reasoning as
# public.sh), `fields` (board Status/Score) is not carried — this feed lists
# changes awaiting a check, it does not rank them; ranking is the desk's job and
# PRs are not on the desk.
#
# `claimed` IS 0 BY CONSTRUCTION, AND IS KEPT ONLY UNTIL THE DESK STOPS READING
# IT (#7). For a PR row the board's `claimed` is the `claimed` label or an
# assignee ON THE PULL REQUEST — and the claim convention never writes a claim
# onto a PR; both doors write onto an ISSUE. So it can never be true, and
# prs.bounded.tools has been rendering a count that cannot be non-zero as though
# it were measured. `desk`#15 switches the page to `claim_check`; dropping this
# field is the separate change after that, because the two repos deploy
# independently and removing it first blanks the page in between.
#
# `claim_check` IS the question that field was reaching for: the verdict of the
# `pr-claim` gate (`.github-private`#723) — does this PR name an issue carrying a
# live claim. Added upstream by pr-claim.sh, which reads the CHECK RUN and never
# opens an issue, so no issue title, number or claimant can reach this filter to
# be published. Allowlisted key by key below all the same: if that object ever
# grows a field that DOES name an issue, it must not ride in on a `claim_check`
# nobody re-read.
set -euo pipefail

jq '
  {
    generated_at: .generated_at,
    feed: "front-desk-prs-public",
    visibility_filter: "repo_private == false (default-deny)",
    project: { org: .project.org, number: .project.number, title: .project.title },
    items: [
      .items[]
      | select(.repo != null)
      | select(.repo_private == false)
      | select(.type == "PullRequest")
      | select(.issue_state == "OPEN")
      | {
          repo: .repo,
          number: .number,
          title: .title,
          url: .url,
          labels: .labels,
          claimed: .claimed,
          claim_check: { state: (.claim_check.state // "unknown"),
                         conclusion: .claim_check.conclusion,
                         url: .claim_check.url }
        }
    ]
  }
  | .item_count = (.items | length)
  # Recomputed over the FILTERED set, never carried through from the snapshot —
  # the rule scripts/README.md says must not be relaxed. Snapshot totals
  # cover private rows, and the delta between the two is itself a private fact.
  | .claim_counts = ( (.items | map(.claim_check.state) | group_by(.)
                       | map({ (.[0]): length }) | add // {}) as $seen
                      | { compliant: 0, non_compliant: 0, not_measured: 0,
                          pending: 0, unknown: 0 } + $seen )
'
