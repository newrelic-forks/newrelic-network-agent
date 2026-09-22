# Releasing

How a version goes from a `VERSION` bump to a released Docker Hub image, and the one manual
step in the middle of that.

## The model

`VERSION` (repo root) is the single source of truth for what gets released — not a fallback
default. It only ever holds a bare `MAJOR.MINOR.PATCH` (never `-rc1`, `-alpha`, etc.), and
the commit that bumps it is the *exact* commit that gets tagged and released. There's no
separate release-candidate tag: the same tag and the same GitHub release object exist from
the moment `VERSION` is bumped through to the final promoted release. "Pre-release" vs.
"release" is purely GitHub's own checkbox on that one object, not a different tag.

That's deliberately simpler than keeping a `-rc1` suffix around: it means there's never a
"which commit does the full release tag point at" question (see `git log` history before
this model — that question is exactly what an earlier version of this doc, and this
Justfile's now-removed `release-rc`/`release-promote from_tag` recipes, existed to answer by
pinning commits explicitly). The cost is that a failed pre-release burns a version number —
if `0.0.5`'s pre-release fails testing, the fix goes out as `0.0.6`, not a re-spun `0.0.5`.
That's fine; version numbers are free.

## The pipeline

1. **Bump `VERSION`** in a PR to a bare, strictly-increasing `MAJOR.MINOR.PATCH` (e.g.
   `0.0.4` → `0.0.5`). `version-format-check.yml` enforces the format, the no-prerelease-
   suffix rule, and the increment on every PR that touches it — get it wrong and the PR's
   checks fail before anyone reviews it.
2. **Merge it.** That push to `main` triggers `cut-prerelease.yml`, which re-validates
   everything itself (it doesn't trust the PR-time gate — see its own comments for why),
   then tags that commit `v0.0.5` and opens a GitHub **pre-release** for it. This build runs
   behind the `docker-hub-prerelease` environment, so it pauses for a required reviewer's
   approval before anything actually gets pushed to Docker Hub.
3. **`publish-release.yml` picks up the new pre-release** (it triggers on `release: published`)
   and pushes `newrelic/network-agent:0.0.5` and `newrelic/network-agent:sha-<commit>`.
   Both tags are immutable from this point on.
4. **Test it.** Pull `0.0.5` (or the `sha-<commit>` tag), run canary/manual testing, whatever
   this release needs.
   - If it fails: fix the problem, bump `VERSION` again (`0.0.6`), and go back to step 1.
     Never reuse or move the `v0.0.5` tag.
   - If it passes: promote it.
5. **Promote:** `just release-promote 0.0.5`, or equivalently, edit the `v0.0.5` release on
   GitHub and uncheck "This is a pre-release." Either way, this flips the *same* release
   object's pre-release flag off, which fires GitHub's `released` event.
   `publish-release.yml`'s `promote` job picks that up, and — behind the
   `docker-hub-release` environment's own required-reviewer approval — retags the
   already-pushed `sha-<commit>` image as `0.0.5` and `latest`. **No rebuild.** What ships as
   the real release is byte-for-byte what was tested in step 4.

Two independent human gates in that pipeline: PR review gates *cutting* a candidate (step
1-2), a required reviewer on `docker-hub-release` gates *promoting* it (step 5) — separate
from whoever approved the pre-release build itself in step 2.

## `just release-promote <version>`

Wraps step 5. Before touching anything, it checks:

- A GitHub release for `v<version>` exists and is currently marked pre-release (refuses to
  "promote" something that's already a full release, or doesn't exist yet).
- (Best-effort, non-fatal) `publish-release.yml` actually completed successfully for that
  tag — if this can't be confirmed you get a warning, not a hard stop, since the `promote`
  job's own Docker Hub check is the real, unskippable gate.

Then it runs `gh release edit v<version> --prerelease=false`. That's it — there's no
`release-rc` recipe, and no `from_tag` argument here, because there's only ever one release
object per version to edit, never a second tag to resolve or pin.

Needs `gh` authenticated (`gh auth login` — available in `nix develop`'s devShell).

## Why there's no `release-rc` recipe

Cutting a pre-release is `cut-prerelease.yml`'s job now, triggered by the `VERSION` bump
itself — there's deliberately no CLI or UI path that creates a tag/release without a
corresponding `VERSION` bump landing on `main` first. Introducing one would let the
checked-in `VERSION` (which Nix's `packages.*.network-agent`, the `Makefile`'s default, and
`publish-release.yml`'s `workflow_dispatch` fallback all read) drift from whatever's actually
been tagged. If you need an ad-hoc build+push outside this pipeline entirely (not a real
release), that's what `publish-release.yml`'s `workflow_dispatch` input is for — it never
touches `VERSION`, never tags anything, and never promotes.
