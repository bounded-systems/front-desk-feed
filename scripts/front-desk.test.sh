#!/usr/bin/env bash
# Behaviour pins for front-desk.sh. No network, no GitHub, no credential.
#
#   bash scripts/front-desk.test.sh
#
# THE REFUSALS ARE TESTED AS HARD AS THE HAPPY PATH, and that is the point of
# this file rather than a nicety. Every failure this reader has is SILENT by
# default: a stale snapshot renders a perfectly convincing page of yesterday's
# ranks, an empty board renders a page with nothing wrong with it, and a
# snapshot with a broken stamp renders whatever `date` guessed. A suite that
# only checked the happy path would pass on all three.
#
# Fixtures are stamped RELATIVE TO NOW, because age is the thing under test and
# a frozen stamp would make the fresh-snapshot cases rot into stale ones.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$here/front-desk.sh"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok   — $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL — $1"; }
check()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want [$3], got [$2])"; fi; }
has()     { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (output does not contain [$3])" ;; esac; }
has_not() { case "$2" in *"$3"*) bad "$1 (output contains [$3])" ;; *) ok "$1" ;; esac; }

ago() { date -u -d "@$(( $(date -u +%s) - $1 ))" +%Y-%m-%dT%H:%M:%SZ; }

out=""; rc=0
run() { set +e; out="$(bash "$SCRIPT" "$@" 2>&1)"; rc=$?; set -e; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
write() { cat > "$tmp/f.json"; echo "$tmp/f.json"; }

# A board with one of everything that must be treated differently. Scores are
# chosen so ranking is unambiguous and so the untriaged rows sit below the
# triaged ones, which is the shape the real feed has.
board() {
  cat <<JSON
{
  "generated_at": "$1",
  "feed": "front-desk-public",
  "visibility_filter": "repo_private == false (default-deny)",
  "project": { "org": "bounded-systems", "number": 2, "title": "Front Desk" },
  "items": [
    { "repo": "bounded-systems/alpha", "number": 1, "title": "top triaged row",
      "url": "https://github.com/bounded-systems/alpha/issues/1", "issue_state": "OPEN",
      "labels": [], "claimed": false, "type": "Issue",
      "fields": { "Status": "Todo", "Score": 16.75, "Effort": 5.0, "Value": 85.0 } },
    { "repo": "bounded-systems/alpha", "number": 2, "title": "second triaged row",
      "url": "https://github.com/bounded-systems/alpha/issues/2", "issue_state": "OPEN",
      "labels": [], "claimed": false, "type": "Issue",
      "fields": { "Status": "Todo", "Score": 9.5, "Effort": 3.0, "Value": 40.0 } },
    { "repo": "bounded-systems/beta", "number": 3, "title": "an UNTRIAGED row, scored low for want of a Value",
      "url": "https://github.com/bounded-systems/beta/issues/3", "issue_state": "OPEN",
      "labels": [], "claimed": false, "type": "Issue",
      "fields": { "Status": "Todo", "Score": 1.5 } },
    { "repo": "bounded-systems/beta", "number": 4, "title": "another untriaged row",
      "url": "https://github.com/bounded-systems/beta/issues/4", "issue_state": "OPEN",
      "labels": [], "claimed": false, "type": "Issue",
      "fields": { "Status": "Todo", "Score": 1.1 } },
    { "repo": "bounded-systems/gamma", "number": 5, "title": "SOMEONE-ELSES-WORK",
      "url": "https://github.com/bounded-systems/gamma/issues/5", "issue_state": "OPEN",
      "labels": ["claimed"], "claimed": true, "type": "Issue",
      "fields": { "Status": "Todo", "Score": 20.0, "Effort": 1.0, "Value": 99.0 } },
    { "repo": "bounded-systems/gamma", "number": 6, "title": "CLOSED-BUT-STILL-TODO",
      "url": "https://github.com/bounded-systems/gamma/issues/6", "issue_state": "CLOSED",
      "labels": [], "claimed": false, "type": "Issue",
      "fields": { "Status": "Todo", "Score": 19.0, "Effort": 1.0, "Value": 90.0 } },
    { "repo": "bounded-systems/delta", "number": 7, "title": "A-PULL-REQUEST-NOT-CLAIMABLE-WORK",
      "url": "https://github.com/bounded-systems/delta/pull/7", "issue_state": "OPEN",
      "labels": [], "claimed": false, "type": "PullRequest",
      "fields": { "Status": "Todo", "Score": 18.0, "Effort": 1.0, "Value": 95.0 } },
    { "repo": "bounded-systems/alpha", "number": 8, "title": "finished work",
      "url": "https://github.com/bounded-systems/alpha/issues/8", "issue_state": "CLOSED",
      "labels": [], "claimed": false, "type": "Issue",
      "fields": { "Status": "Done", "Score": 4.0, "Effort": 1.0, "Value": 10.0 } }
  ],
  "counts": { "Todo": 5, "Done": 1 },
  "item_count": 8
}
JSON
}

echo "── the happy path"
fresh="$(board "$(ago 600)" | write)"
run --file "$fresh" --all
check "a fresh snapshot renders and exits 0" "$rc" "0"

# #431: print its own age. Not "recently" — the stamp and an elapsed figure.
has "the render prints the snapshot's own stamp" "$out" "$(ago 600)"
has "the render prints an elapsed age, not just a timestamp" "$out" "10m old"

# Requirement 3: the public-half caveat is SAID, not implied.
has "the render states the visibility filter it was given" "$out" "repo_private == false (default-deny)"
has "the render says private rows are absent" "$out" "ABSENT"
has "the render refuses to be called 'the board'" "$out" 'NOT "the board"'

# #908/#909: the triage split is disclosed, with the counts measured from the
# snapshot rather than asserted.
has "the render says the order is triaged-first, not importance-first" "$out" "triaged first, NOT most important first"
has "the render counts the triaged rows" "$out" "2 are triaged"
has "the render counts the untriaged rows" "$out" "2 are not"
has "the render says a low score usually means untriaged" "$out" "UNTRIAGED, NOT UNIMPORTANT"

# THE FAILURE #909 NAMES: an unscored row and a deprioritised row rendering
# identically. The marker is what makes them distinguishable, so pin it on the
# row itself, not just in the prose above.
rows="$(sed -n '/^Claimable/,/^$/p' <<<"$out")"
has "an untriaged row is marked on its own line" "$rows" "untriaged  bounded-systems/beta#3"
has_not "a triaged row is NOT marked untriaged" "$(grep 'alpha#1' <<<"$rows")" "untriaged"

check "the top-ranked row is the highest-scoring claimable one" \
  "$(grep -c 'alpha#1' <<<"$rows")" "1"
check "ranking is descending: alpha#1 precedes alpha#2" \
  "$(grep -n -e 'alpha#1' -e 'alpha#2' <<<"$rows" | head -1 | grep -c 'alpha#1')" "1"

echo
echo "── what is held back, and counted"
# Requirement 4, and the guard rather than the printed number: a PR row that
# DOES reach this feed must not render as claimable.
has_not "a PullRequest row does not appear in the claimable list" "$rows" "A-PULL-REQUEST-NOT-CLAIMABLE-WORK"
has "the withheld PR count is printed" "$out" "1  pull requests"
has_not "a row already marked claimed does not appear" "$rows" "SOMEONE-ELSES-WORK"
has "the withheld claimed count is printed" "$out" "1  marked claimed"
has_not "a closed Todo row does not appear" "$rows" "CLOSED-BUT-STILL-TODO"
has "the withheld closed count is printed" "$out" "1  Todo but closed"
check "exactly the four claimable rows are listed" \
  "$(grep -c 'bounded-systems/' <<<"$rows")" "4"

echo
echo "── the limit that has to reach the OUTPUT, not a comment (#15)"
has "the render says the rows are nameable, not free" "$out" "NAMEABLE, not free"
has "the render says the feed carries no lease or fencing state" "$out" "no lease and no fencing state"
has "the render says held items are excluded upstream, not marked" "$out" "excluded upstream rather than marked"
has "the render refuses to claim an item is unclaimed now" "$out" "unclaimed NOW"

echo
echo "── refusal: stale (#431) — and it does not guess WHY (#898)"
run --file "$(board "$(ago 20000)" | write)" --all
check "a stale snapshot exits non-zero" "$rc" "3"
has "the stale banner is printed" "$out" "STALE"
has "the stale banner states the age" "$out" "5h 33m old"
# The half that is easy to drop. From here a stopped lane and a dropped cron
# slot are the same observation, so the banner must decline to name a cause.
has "the stale banner explicitly disclaims knowing why" "$out" "does NOT know why"
has_not "the stale banner does not assert the lane stopped" "$out" "lane stopped"
has_not "the stale banner does not assert the lane is down" "$out" "lane is down"
# A stale board is still served, loudly — a reader that printed nothing would
# be less useful than one that prints and says so.
has "a stale render still lists the ranked page" "$out" "alpha#1"

run --file "$(board "$(ago 20000)" | write)" --max-age 30000 --all
check "--max-age raises the threshold and the same snapshot passes" "$rc" "0"
has_not "the raised threshold suppresses the banner" "$out" "STALE"

echo
echo "── refusal: a snapshot that cannot state its age"
run --file "$(board "$(ago 600)" | jq 'del(.generated_at)' | write)"
check "a snapshot with no generated_at is refused" "$rc" "2"
has "and says so" "$out" "cannot state its age"

run --file "$(board "not-a-timestamp" | write)"
check "an unparseable stamp is refused" "$rc" "2"

# THE SHARP ONE. GNU `date -d 2026` succeeds and returns a confident wrong
# instant, which would render a four-year-old board as merely stale — or as
# fresh, on the right day. Shape is validated before `date` is ever asked.
run --file "$(board "2026" | write)"
check "a loose stamp date(1) would happily accept is refused" "$rc" "2"
has "and names the field rather than guessing" "$out" "not an ISO-8601 UTC instant"

run --file "$(board "$(ago 600)" | jq '.generated_at = 1757467143' | write)"
check "a numeric epoch stamp is refused rather than guessed at" "$rc" "2"

echo
echo "── refusal: not a board at all"
run --file "$(board "$(ago 600)" | jq '.items = []' | write)"
check "a feed carrying zero rows is refused" "$rc" "4"
has "and says an empty board is indistinguishable from a broken filter" "$out" "broken filter"

printf 'not json at all {{' > "$tmp/bad.json"
run --file "$tmp/bad.json"
check "unparseable JSON is refused" "$rc" "2"

run --file "$(board "$(ago 600)" | jq 'del(.feed)' | write)"
check "a snapshot that does not name itself is refused" "$rc" "2"
has "and refuses to render an unidentified snapshot as the board" "$out" "unidentified snapshot"

# The two feeds this repo publishes answer different questions. Rendering the
# PR feed as the desk would present changes-awaiting-a-check as claimable work,
# which is the same failure the PR guard above prevents, one layer up.
run --file "$(board "$(ago 600)" | jq '.feed = "front-desk-prs-public"' | write)"
check "the PR feed is refused when handed to the desk reader" "$rc" "2"
has "and says which feed it was given" "$out" "front-desk-prs-public"

run --file "$tmp/does-not-exist.json"
check "an unreadable path is refused" "$rc" "2"

echo
echo "── an empty claimable page is an ANSWER, not an empty page"
# Non-empty board, nothing claimable. This must NOT be silently blank: a reader
# that printed an empty list here is indistinguishable from one whose filter
# broke.
run --file "$(board "$(ago 600)" | jq '.items |= map(.claimed = true)' | write)"
check "a board with nothing claimable still exits 0" "$rc" "0"
has "and says so in words" "$out" "That is a real answer, not an error"
has "and still prints the public-half caveat" "$out" "repo_private == false"
has "and still prints the nameable-not-free limit" "$out" "NAMEABLE, not free"

echo
echo "── plumbing"
run --file "$(board "$(ago 600)" | write)" --top 1
check "--top limits the rows shown" \
  "$(sed -n '/^Claimable/,/^$/p' <<<"$out" | grep -c 'bounded-systems/')" "1"
has "--top still reports the full claimable total" "$out" "(4 rows, 1 shown)"

run --file "$(board "$(ago 600)" | write)" --top nonsense
check "a non-numeric --top is a usage error" "$rc" "64"
run --nope
check "an unknown argument is a usage error" "$rc" "64"
run --help
check "--help exits 0" "$rc" "0"

# stdin, so a session can pipe a snapshot it already has without a temp file.
set +e
out="$(board "$(ago 600)" | bash "$SCRIPT" --file - --top 1 2>&1)"; rc=$?
set -e
check "a snapshot on stdin renders" "$rc" "0"
has "and ranks it the same way" "$out" "alpha#1"

# A stamp in the future is not staleness and must not be reported as it.
run --file "$(board "$(ago -7200)" | write)"
check "a future-stamped snapshot does not exit stale" "$rc" "0"
has "but is flagged" "$out" "IN THE FUTURE"

echo
echo "front-desk.test.sh: $pass ok, $fail failed"
[ "$fail" -eq 0 ]
