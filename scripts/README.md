# The query and the filter

`project.sh` queries org project #2 and transforms it into a snapshot.
`public.sh` reduces that snapshot to the rows and fields that may be published.

Both are carried here **in full**, as copies of the versions that run in
`bounded-systems/.github-private`'s projection lane.

## Why copies, and not an import

This repo is public by necessity: consumers fetch the feed anonymously, and a
feed nobody can audit is not meaningfully verifiable. Signing it makes that worse
rather than better if the code producing it is unreadable — a signature over an
artifact of unknown provenance only certifies *who* produced it, never *what they
did*. So the code that produces a signed public artifact is readable by the
people asked to trust the signature.

Referencing `.github-private` was the alternative, and it fails on the same
point: no consumer can open it.

## The cost, named

Two implementations of the same query, in repos that cannot check each other —
one private, one public. They will drift.

What bounds the damage is that **drift here cannot become a disclosure**. The
publish lane re-derives both files from one query in one run and refuses to push
unless:

- the filtered row count matches the source's count of rows whose repo is
  positively `repo_private == false`, and
- no repo the snapshot marked private appears in the filtered output.

So a `public.sh` that drifted toward *over*-inclusion fails the run rather than
publishing. A `project.sh` that drifted produces a feed that disagrees with the
private projection about the board — visible as a stale or odd ranking, not as a
leak.

The filter's own default-deny rule is the second bound: a row survives only when
the snapshot positively established that its repo is public. Unknown visibility
(`repo_private: null` — a snapshot predating the field, a DraftIssue with no repo
at all) drops. Unknown is not permission.

## What must not be relaxed

`public.sh` recomputes `counts` over the filtered set rather than carrying the
snapshot's through. That is not tidiness: the difference between the two counts
says how much work sits in private repos, which is itself a private fact. The
publish lane holds the same line — it prints public numbers only, and its
parity error deliberately names neither count, because the delta is the fact.

Diagnose count mismatches from the private projection lane, which may safely say
more.
