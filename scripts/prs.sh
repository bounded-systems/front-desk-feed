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
# public.sh: `claimed` answers the only public question), `fields` (board
# Status/Score) is not carried — this feed lists changes awaiting a check, it
# does not rank them; ranking is the desk's job and PRs are not on the desk.
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
          claimed: .claimed
        }
    ]
  }
  | .item_count = (.items | length)
'
