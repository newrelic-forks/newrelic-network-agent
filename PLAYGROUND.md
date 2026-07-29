# ktranslate — investigation playground

Private fork of [`kentik/ktranslate`](https://github.com/kentik/ktranslate) used as an
internal investigation playground. **Not** wired up to publish anywhere.

## Repos & branches

- **`DavSanchez/ktranslate`** (this repo, private)
  - `main` — faithful copy of `kentik/ktranslate@main`. Keep it pristine; do not add work here.
  - `investigation` — the working branch (CI build, snmp auth, disabled upstream workflows).
- **`DavSanchez/snmp-profiles`** (private) — point-in-time mirror of `kentik/snmp-profiles`.
  The Docker image bakes these SNMP profiles into `/etc/ktranslate/profiles`.

Remotes:

| name | URL |
|------|-----|
| `origin`   | `git@github.com:DavSanchez/ktranslate.git` |
| `upstream` | `git@github.com:kentik/ktranslate.git` |

### Pulling in upstream changes

```bash
git fetch upstream
git checkout main && git merge --ff-only upstream/main && git push origin main
git checkout investigation && git rebase main   # replay playground changes on top
```

## What changed on `investigation`

- **`Dockerfile`** — the snmp-profiles clone gained *opt-in* auth. The upstream override logic
  (`KENTIK_SNMP_PROFILE_REPO`) is byte-for-byte unchanged; a `git config … insteadOf` step is
  added that authenticates GitHub HTTPS clones **only** when a BuildKit secret `github_token`
  is provided (needed for the private mirror). It is a no-op when the secret is absent.
- **`.github/workflows/ci-build.yml`** — builds the image with `push: false` (validation only).
  Triggers on push to `investigation`, on PRs, and via manual dispatch.
- **Inherited kentik workflows** (`publish-*`, `create-release`, `test-on-pr`,
  `clean-stale-issues`) — auto-triggers disabled by reducing each `on:` block to
  `workflow_dispatch:` only, so nothing publishes. Restore the original `on:` blocks
  (they're intact on `main` / in git history) to re-enable.
- **`.dockerignore`** — excludes `.envrc` so local secrets never enter the build context.

## Secrets

**GitHub Actions** (set on this repo — used by `ci-build.yml`):

| secret | purpose |
|--------|---------|
| `MM_ACCOUNT_ID`   | MaxMind account ID (GeoLite2 download) |
| `MM_DOWNLOAD_KEY` | MaxMind license key |
| `SNMP_PROFILES_TOKEN` | fine-grained PAT, read-only Contents on `DavSanchez/snmp-profiles` |

**Local** (`.envrc`, gitignored, loaded by direnv):

- `MM_ACCOUNT_ID`, `MM_DOWNLOAD_KEY`

For the local snmp clone we reuse your `gh` token (`gh auth token`) rather than the PAT.

## CI build (recommended validation path)

Push to `investigation`, or run **"CI Build (no push)"** manually from the Actions tab.
It compiles the Go binary (`make`), downloads the MaxMind DBs, clones the private snmp
mirror via the PAT, and assembles the image — **without pushing it anywhere**. GitHub's
runners have clean network egress and `docker/setup-buildx-action` preinstalls buildx, so
this is the authoritative build check.

## Local build (colima)

Environment notes specific to this machine:

- The `docker` CLI on `PATH` is **Rancher Desktop's** (`~/.rd/bin/docker`), pointed at the
  `colima` context. It ships **no buildx plugin** and ignores `DOCKER_CLI_PLUGIN_EXTRA_DIRS`,
  so we run buildx **standalone** from nix.
- The Dockerfile uses BuildKit (`--mount=type=secret`), so buildx/BuildKit is required
  (Docker 29 has no classic builder anyway).

```bash
cd <repo>
set -a; source ./.envrc; set +a                 # MM_ACCOUNT_ID, MM_DOWNLOAD_KEY
export GH_TOKEN="$(gh auth token)"               # for the private snmp clone

BUILDX="$(nix --extra-experimental-features 'nix-command flakes' \
  build --no-link --print-out-paths nixpkgs#docker-buildx \
  | head -1)/libexec/docker/cli-plugins/docker-buildx"

"$BUILDX" build --builder colima \
  --secret id=github_token,env=GH_TOKEN \
  --build-arg MAXMIND_LICENSE_KEY="$MM_DOWNLOAD_KEY" \
  --build-arg YOUR_ACCOUNT_ID="$MM_ACCOUNT_ID" \
  --build-arg KENTIK_KTRANSLATE_VERSION=local-test \
  --build-arg KENTIK_SNMP_PROFILE_REPO=https://github.com/DavSanchez/snmp-profiles \
  -t ktranslate:local --load .
```

**Known blocker — corporate TLS interception.** On a network with a TLS-intercepting proxy
(e.g. Zscaler/Netskope), the in-build `curl` to MaxMind fails with
`SSL certificate ... self-signed certificate in certificate chain`, because the build
container doesn't trust the corporate root CA. Options: build off that network, or inject the
corporate root CA into the network-using build stages (`maxmind`, `snmp`, `build`) and run
`update-ca-certificates`. CI is unaffected.

## Security note — build-arg credential leakage

MaxMind creds are passed as **build args**, and BuildKit prints the *expanded* `RUN` command
when a step **fails** — so a failed build can leak `-u <account>:<licensekey>` into the logs.
Don't share raw build logs, and **rotate the MaxMind license key if it ever appears in one.**
The clean fix is to convert the MaxMind download to a BuildKit **secret mount** (like
`github_token`) so the value never appears even on failure — a good follow-up.
