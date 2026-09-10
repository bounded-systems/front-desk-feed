#!/usr/bin/env bash
# Read the public Front Desk board FROM A COLD SESSION (#15).
#
#   curl -fsSL -o front-desk.sh \
#     https://raw.githubusercontent.com/bounded-systems/front-desk-feed/main/scripts/front-desk.sh
#   bash front-desk.sh
#
# WHY THIS EXISTS. `.github-private`#431 made `.claude/front-desk.sh` the
# canonical reader and stated that a session cannot read the board any other
# way. That reader lives in `.github-private` and reads the projection branch
# THERE — private, dot-named, and `add_repo` refuses leading-dot names. So the
# one reader the org has is unreachable from exactly the sessions that need it.
#
# This repo already serves the same content with no credential at all. What was
# missing was something to read it with. Measured 2026-09-10 with GH_TOKEN and
# GITHUB_TOKEN unset: the feed fetches 200, and its ranked claimable page
# matched the private projection row for row.
#
# EVERY RULE BELOW IS PORTED, NOT INVENTED. Each was paid for somewhere else and
# the comment says where. A reader that re-derived them would get a different
# answer than the attached reader, and two readers that disagree about the board
# are worse than one reader nobody can reach.
#
# IT LIVES BESIDE THE FEED IT PARSES. `.github-private`#581 built
# context-parity.sh because a consumer and its data in different repos is a
# second place the shape can drift. Putting this in the boot payload or `desk`
# would have rebuilt that gap for the one artifact that still lacked it.
set -euo pipefail

FEED_URL_DEFAULT="https://raw.githubusercontent.com/bounded-systems/front-desk-feed/feed/front-desk-public.json"

# WHY THREE HOURS. The publish lane is `cron: 35 * * * *` plus a
# repository_dispatch on board changes, so a healthy feed is minutes old, not
# hours. Three hours is not a claim that the lane is down — see the banner
# below; it is the point past which these ranks are old enough that acting on
# them can send you at work that is already someone else's, which is the harm
# `.github-private`#431 named. Override for a slower tolerance:
#   FRONT_DESK_MAX_AGE=21600 bash front-desk.sh
MAX_AGE_DEFAULT=10800

# Exit codes, so a caller can branch without scraping the render.
EX_USAGE=64      # bad invocation
EX_UNUSABLE=2    # not a feed, unparseable, or no usable stamp
EX_STALE=3       # a real board, too old to act on
EX_EMPTY=4       # a feed carrying no rows at all

feed_url="${FRONT_DESK_FEED_URL:-$FEED_URL_DEFAULT}"
max_age="${FRONT_DESK_MAX_AGE:-$MAX_AGE_DEFAULT}"
feed_file=""
top=20

usage() {
  cat <<'USAGE'
front-desk.sh — the public Front Desk board, readable without a credential.

  bash front-desk.sh                 fetch and render the live feed
  bash front-desk.sh --file F        render a local snapshot (no network)
  cat F | bash front-desk.sh --file - render a snapshot on stdin

Options
  --file PATH   read a snapshot instead of fetching ("-" for stdin)
  --top N       show N claimable rows (default 20)
  --all         show every claimable row
  --max-age S   seconds before the snapshot is called stale (default 10800)
  -h, --help    this

Environment
  FRONT_DESK_FEED_URL   override the feed location
  FRONT_DESK_MAX_AGE    same as --max-age

Exit
  0 rendered   2 unusable feed   3 stale   4 empty board   64 usage
USAGE
}

die() { echo "front-desk: $2" >&2; exit "$1"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --file) [ $# -ge 2 ] || die "$EX_USAGE" "--file needs a path"; feed_file="$2"; shift 2 ;;
    --top)  [ $# -ge 2 ] || die "$EX_USAGE" "--top needs a number"; top="$2";  shift 2 ;;
    --all)  top=0; shift ;;
    --max-age) [ $# -ge 2 ] || die "$EX_USAGE" "--max-age needs seconds"; max_age="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "$EX_USAGE" "unknown argument: $1" ;;
  esac
done

case "$top" in *[!0-9]*|"") die "$EX_USAGE" "--top wants a whole number, got: $top" ;; esac
case "$max_age" in *[!0-9]*|"") die "$EX_USAGE" "--max-age wants whole seconds, got: $max_age" ;; esac

command -v jq >/dev/null 2>&1 || die "$EX_USAGE" "jq is required and was not found on PATH."

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
snapshot="$tmp/feed.json"
source_label=""
digest_note="not checked — a local snapshot carries no published digest"

if [ -n "$feed_file" ]; then
  if [ "$feed_file" = "-" ]; then
    cat > "$snapshot"; source_label="(stdin)"
  else
    [ -r "$feed_file" ] || die "$EX_UNUSABLE" "cannot read $feed_file"
    cp "$feed_file" "$snapshot"; source_label="$feed_file"
  fi
else
  command -v curl >/dev/null 2>&1 || die "$EX_USAGE" "curl is required to fetch the feed."
  source_label="$feed_url"
  # NO CREDENTIAL, DELIBERATELY. The whole point of this reader is that it works
  # from a session that has none, so the fetch must never reach for one.
  curl -fsSL --retry 3 --retry-connrefused --connect-timeout 5 --max-time 60 \
    -o "$snapshot" "$feed_url" \
    || die "$EX_UNUSABLE" "could not fetch the feed from $feed_url"

  # The cheap integrity check README.md publishes the digest for. A mismatch is
  # refused rather than warned about: a reader that renders bytes it has already
  # been told are wrong is worse than one that stops.
  if curl -fsSL --connect-timeout 5 --max-time 20 -o "$tmp/want.sha256" "$feed_url.sha256" 2>/dev/null; then
    want="$(tr -cd '0-9a-f' < "$tmp/want.sha256" | head -c 64)"
    got="$(sha256sum "$snapshot" 2>/dev/null | cut -d' ' -f1)" || got=""
    if [ -z "$got" ]; then
      digest_note="not checked — no sha256sum on PATH"
    elif [ "$want" = "$got" ]; then
      digest_note="${got:0:12}… matches the published .sha256"
    else
      die "$EX_UNUSABLE" "DIGEST MISMATCH — the feed does not hash to its published .sha256. Refusing to render it."
    fi
  else
    digest_note="not checked — the published .sha256 could not be fetched"
  fi
fi

jq -e . "$snapshot" >/dev/null 2>&1 \
  || die "$EX_UNUSABLE" "$source_label is not parseable JSON."

# NAME CHECK BEFORE ANY RENDER. This repo publishes two feeds and they answer
# different questions; front-desk-prs-public is a list of changes awaiting a
# check, not a queue of claimable work (public.sh, prs.sh). Rendering one as the
# other would present PRs as claimable, which is precisely the rule ported
# further down.
feed_name="$(jq -r '.feed // ""' "$snapshot")"
case "$feed_name" in
  front-desk-public) : ;;
  front-desk-prs-public)
    die "$EX_UNUSABLE" "that is the PR feed (front-desk-prs-public), not the desk. It lists changes awaiting a check, not claimable work." ;;
  "") die "$EX_UNUSABLE" "$source_label does not name itself as a feed. Refusing to render an unidentified snapshot as the board." ;;
  *)  die "$EX_UNUSABLE" "unexpected feed name '$feed_name' — expected front-desk-public." ;;
esac

# A SNAPSHOT THAT CANNOT STATE ITS AGE IS NOT A BOARD. README.md applies that
# rule to the filter; it holds at least as hard here, because everything below
# depends on knowing how old this is. Validated by shape first: GNU `date -d`
# will happily read "2026" as a year and hand back a confident wrong answer.
stamp="$(jq -r '.generated_at // ""' "$snapshot")"
[ -n "$stamp" ] \
  || die "$EX_UNUSABLE" "the snapshot carries no generated_at. It cannot state its age, so it is not a board this reader will render."
case "$stamp" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) : ;;
  *) die "$EX_UNUSABLE" "generated_at is not an ISO-8601 UTC instant: '$stamp'. Refusing to guess how old this is." ;;
esac

to_epoch() {
  date -u -d "$1" +%s 2>/dev/null && return 0
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null && return 0
  return 1
}
gen_epoch="$(to_epoch "$stamp")" \
  || die "$EX_UNUSABLE" "could not convert generated_at '$stamp' to an instant."
now_epoch="$(date -u +%s)"
age=$(( now_epoch - gen_epoch ))

human_age() {
  local s="$1" sign=""
  if [ "$s" -lt 0 ]; then sign="-"; s=$(( -s )); fi
  local d=$(( s / 86400 )) h=$(( (s % 86400) / 3600 )) m=$(( (s % 3600) / 60 ))
  if   [ "$d" -gt 0 ]; then printf '%s%dd %dh' "$sign" "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%s%dh %dm' "$sign" "$h" "$m"
  else                      printf '%s%dm' "$sign" "$m"
  fi
}

IFS=$'\t' read -r n_all n_prs n_todo n_todo_closed n_held n_claim n_triaged n_untriaged n_repos n_open n_scored <<EOF
$(jq -r '
  (.items // []) as $all
  | [ $all[] | select(.type == "PullRequest") ]                       as $prs
  | [ $all[] | select(.type != "PullRequest") ]                       as $work
  | [ $work[] | select((.fields.Status // "") == "Todo") ]            as $todo
  | [ $todo[] | select(.issue_state == "OPEN") ]                      as $open
  | [ $open[] | select(.claimed == true) ]                            as $held
  | [ $open[] | select(.claimed != true) ]                            as $claim
  | [ ($all | length),
      ($prs | length),
      ($todo | length),
      (($todo | length) - ($open | length)),
      ($held | length),
      ($claim | length),
      ([ $claim[] | select(.fields.Value != null) ] | length),
      ([ $claim[] | select(.fields.Value == null) ] | length),
      ([ $all[] | .repo // empty ] | unique | length),
      ([ $all[] | select(.issue_state == "OPEN") ] | length),
      ([ $all[] | select(.fields.Score != null) ] | length)
    ] | @tsv' "$snapshot")
EOF

[ "${n_all:-0}" -gt 0 ] \
  || die "$EX_EMPTY" "the feed carries zero rows. An empty board and a broken filter render identically, so this refuses rather than showing you an empty page."

declared_filter="$(jq -r '.visibility_filter // ""' "$snapshot")"
[ -n "$declared_filter" ] || declared_filter="(the snapshot did not declare one)"
project="$(jq -r '"\(.project.org // "?") project #\(.project.number // "?")"' "$snapshot")"

# ── the render ──────────────────────────────────────────────────────────────
echo
echo "Front Desk — public feed"
echo "  snapshot   $stamp  ($(human_age "$age") old)"
echo "  source     $source_label"
echo "  digest     $digest_note"
echo "  board      $project — $n_all rows, $n_open open, $n_todo Todo, across $n_repos repos"
echo

stale=0
if [ "$age" -gt "$max_age" ]; then
  stale=1
  # PORTED FROM #431, AND #898 IS THE HALF THAT IS EASY TO DROP. The banner
  # says HOW old and refuses to say WHY, because from here a stopped publish
  # lane and a dropped cron slot are the same observation. publish.yml's own
  # notes record healthy runs that missed six consecutive slots. A reader that
  # guessed "the lane is down" would be confidently wrong most of the time.
  echo "  ██ STALE — this snapshot is $(human_age "$age") old, past the $(human_age "$max_age") threshold."
  echo "     This reader does NOT know why, and will not guess. A stopped publish"
  echo "     lane and a dropped cron slot look identical from here."
  echo "     Treat every rank below as possibly superseded."
  echo
elif [ "$age" -lt -300 ]; then
  echo "  ██ The snapshot is stamped $(human_age "$age" | tr -d '-') IN THE FUTURE."
  echo "     Either a clock is wrong or this is not the snapshot it says it is."
  echo
fi

cat <<SCOPE
Scope — the public half, and only that
  visibility_filter: $declared_filter
  Rows in private repos are ABSENT from this feed. That is not a defect for a
  cold session (one that cannot reach a private repo cannot act on its rows
  either), but it means this is NOT "the board" — it is the public half of it.
  Anything you conclude about org-wide totals from this page is wrong.

SCOPE

cat <<TRIAGE
Ranking — triaged first, NOT most important first
  Score leans on Value, and only a minority of rows carry Value: $n_scored of
  $n_all rows are scored at all. Of the $n_claim claimable rows below,
  $n_triaged are triaged (carry Value) and $n_untriaged are not.
  So a LOW SCORE HERE USUALLY MEANS UNTRIAGED, NOT UNIMPORTANT. Untriaged rows
  are marked below, because otherwise an unscored row and a deliberately
  deprioritised row render identically and you cannot tell which you are
  looking at.

TRIAGE

if [ "$n_claim" -eq 0 ]; then
  echo "Claimable — Todo, open, not marked claimed"
  echo "  Nothing. Every Todo row in this snapshot is closed, or already marked"
  echo "  claimed. That is a real answer, not an error."
  echo
else
  shown="$n_claim"
  if [ "$top" -gt 0 ] && [ "$top" -lt "$n_claim" ]; then shown="$top"; fi
  echo "Claimable — Todo, open, not marked claimed  ($n_claim rows, $shown shown)"
  jq -r --argjson top "$top" '
    [ (.items // [])[]
      # PRs ARE HELD BACK HERE, not merely counted below. A PR is a change
      # awaiting a check, not claimable work (`.github-private`#480).
      | select(.type != "PullRequest")
      | select((.fields.Status // "") == "Todo")
      | select(.issue_state == "OPEN")
      | select(.claimed != true) ]
    # Descending score. Rows with no Score at all sort last rather than first:
    # a missing score is the least-known row, not the best one.
    | sort_by([ -(.fields.Score // -1e9), (.repo // ""), (.number // 0) ])
    | (if $top > 0 then .[0:$top] else . end)
    | .[]
    # EVERY FIELD IS NON-EMPTY ON PURPOSE. Tab is an IFS *whitespace* character,
    # so `read` collapses runs of tabs and an empty column silently shifts every
    # column after it. The sentinels below are unpacked in the loop.
    | [ (if .fields.Score == null then "?" else (.fields.Score | tostring) end),
        (if .fields.Value == null then "untriaged" else "." end),
        ((.repo // "?") + "#" + ((.number // 0) | tostring)),
        (.title // "(no title)" | gsub("[\t\r\n]"; " ")) ] | @tsv' "$snapshot" \
  | while IFS=$'\t' read -r score triage ref title; do
      [ "$score" != "?" ] || score="—"
      [ "$triage" != "." ] || triage=""
      [ ${#title} -le 52 ] || title="${title:0:51}…"
      printf '  %6s  %-9s  %-36s  %s\n' "$score" "$triage" "$ref" "$title"
    done
  echo
fi

# PORTED: PRs ARE HELD BACK AND THE COUNT IS PRINTED. A PR is a change awaiting
# a check, not claimable work (`.github-private`#480). Here the count is 0 and
# is EXPECTED to be 0 — public.sh drops PR rows and publish.yml refuses to push
# a feed containing one — so this line is a check on that assumption rather
# than a filter doing daily work. It is printed anyway: the day it reads
# non-zero, the feed's shape changed under every consumer, and a guard that
# only reports when it fires never tells you it stopped being true.
echo "Withheld from that list"
echo "  $n_held  marked claimed as of the snapshot above"
echo "  $n_todo_closed  Todo but closed"
echo "  $n_prs  pull requests (expected 0 — this feed carries none by construction;"
echo "     they live in front-desk-prs-public)"
echo

# THE LIMIT THAT MUST REACH THE OUTPUT, not just a comment (#15). The cold probe
# that produced this reader found it and it is the easiest thing here to lose.
cat <<'LIMIT'
What this list is NOT
  These rows are NAMEABLE, not free.
  The feed carries no lease and no fencing state of any kind. `claimed` is a
  label-and-assignee marker as it stood AT THE SNAPSHOT ABOVE — it is not a
  lease, and held items are excluded upstream rather than marked, so their
  absence here is not evidence either. Nothing on this page has told you an
  item is unclaimed NOW.
  Use it to NAME an issue, then claim it through a door and let the door — which
  does hold a lease — decide whether you got it.
LIMIT
echo

[ "$stale" -eq 0 ] || exit "$EX_STALE"
