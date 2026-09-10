# front-desk-feed

Publishes the public half of the Front Desk board as a cosign-signed snapshot,
for anyone to fetch and verify.

## Fetch it

```sh
curl -fsSL https://raw.githubusercontent.com/bounded-systems/front-desk-feed/feed/front-desk-public.json
```

The `feed` branch is a single parentless commit, force-pushed hourly. It carries:

| file | |
| --- | --- |
| `front-desk-public.json` | the feed |
| `front-desk-public.json.sig` | cosign signature (keyless) |
| `front-desk-public.json.pem` | the signing certificate |
| `front-desk-public.json.sha256` | digest, for a cheap integrity check |

## Read it

The feed is a ranked board, and a raw 400 KB of JSON is not one. `scripts/front-desk.sh`
renders it — no credential, no clone, no `jq` incantation to remember:

```sh
curl -fsSL -o front-desk.sh \
  https://raw.githubusercontent.com/bounded-systems/front-desk-feed/main/scripts/front-desk.sh
bash front-desk.sh
```

It exists because the canonical reader does not reach here. `.claude/front-desk.sh`
lives in `.github-private` and reads the projection branch there — private,
dot-named, and `add_repo` refuses leading-dot names — so the one reader the org
had was unreachable from exactly the sessions that need it (#15).

It prints the snapshot's age and **exits non-zero when stale**, without claiming
to know why it is stale; a stopped publish lane and a dropped cron slot are the
same observation from a reader. It discloses the triaged/untriaged split, because
`Score` leans on `Value` and only a minority of rows carry one — the order is
"triaged first", not "most important first", and a low score usually means
nobody has scored it. It says on the page that it covers the public half only.
And it holds pull requests back from the claimable list, printing the count.

The one thing it is careful **not** to tell you: that anything on it is free.
Feed rows carry no lease and no fencing state, and held items are excluded
upstream rather than marked, so the page names work you could claim — it does
not report what is unclaimed now. Claim through a door and let the door decide.

It lives here, beside the data it parses, rather than in the boot payload or
`desk`. A consumer and its feed in separate repos is a second place the shape
can drift — the failure `.github-private`'s `context-parity.sh` exists to
prevent for the other public artifact.

## Verify it

The signature is keyless, so the certificate — not a stored public key — is what
identifies the signer. Pin **this repo and this workflow**:

```sh
cosign verify-blob front-desk-public.json \
  --signature front-desk-public.json.sig \
  --certificate front-desk-public.json.pem \
  --certificate-identity-regexp '^https://github.com/bounded-systems/front-desk-feed/\.github/workflows/publish\.yml@' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

That regexp is the whole reason this repo exists and does one thing. A feed
signed from a repo with twenty unrelated workflows would ask you to accept a
signature from any of them; here the pinned identity means what it says.

Verification is not free, and not every consumer can afford it on every read —
a Worker rendering the board per request cannot do a keyless verification per
request. Such consumers get TLS plus this repo's identity, and the signature
stays available for anything that verifies out of band. Publishing it costs
nothing and keeps the stronger check open.

## What is in it

The board's own ranking, filtered. A row survives only when the snapshot
**positively established** that its repo is public — `repo_private == false`
exactly. Unknown visibility drops: unknown is not permission, and the failure
direction that matters is "too little published", never "a private title on the
internet".

Fields are allowlisted too, so a column added upstream cannot ride along just
because nobody thought about it here.

`counts` are recomputed over the filtered set. The snapshot's own counts are
deliberately not carried: the difference between them says how much work sits in
private repos, which is itself a private fact.

## What it is not

Not a claim door, and not authentication of any kind. It is a read surface — a
filtered copy of a ranking the org already made.

It is also **not the whole board**. A public feed shows public rows by
construction, so a consumer rendering it should not describe it as "the board".

## Freshness

Every snapshot carries `generated_at`. The lane publishes hourly; anything much
older than that means the lane stopped, and a consumer should say so rather than
quietly serving old ranks. A snapshot that cannot state its age is not a board —
the filter refuses to produce one.

## How it is produced

`.github/workflows/publish.yml` — mints a short-lived, broker-issued token over
Actions OIDC (no App key in this repo), queries the board, filters it, signs the
result, and force-pushes the `feed` branch. The full board never leaves the
runner, and this repo's public logs and job summaries carry public numbers only.

See [`scripts/README.md`](scripts/README.md) for why the query and filter live
here in full rather than being imported, and what that costs.
