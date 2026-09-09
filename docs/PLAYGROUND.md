# ntranslate — investigation playground

Private fork of [`kentik/ktranslate`](https://github.com/kentik/ktranslate) used as an
internal investigation playground. **Not** wired up to publish anywhere. (The repo is named
`ntranslate`; the software/binary is still upstream `ktranslate`.)

## Repos & branches

- **`DavSanchez/ntranslate`** (this repo, private)
  - `main` — faithful copy of `kentik/ktranslate@main`. Keep it pristine; do not add work here.
  - `develop` — the working branch (CI build, snmp auth, disabled upstream workflows).
- **`newrelic-forks/snmp-profiles`** (public) — point-in-time mirror of `kentik/snmp-profiles`.
  The Docker image bakes these SNMP profiles into `/etc/ktranslate/profiles`.

Remotes:

| name | URL |
|------|-----|
| `origin`   | `git@github.com:DavSanchez/ntranslate.git` |
| `upstream` | `git@github.com:kentik/ktranslate.git` |

### Pulling in upstream changes

```bash
git fetch upstream
git checkout main && git merge --ff-only upstream/main && git push origin main
git checkout develop && git rebase main   # replay playground changes on top
```

## What changed on `develop`

- **`Dockerfile`**
  - The snmp-profiles clone gained *opt-in* auth. The upstream override logic
    (`KENTIK_SNMP_PROFILE_REPO`) is unchanged; a `git config … insteadOf` step authenticates
    GitHub HTTPS clones **only** when a BuildKit secret `github_token` is provided (for the
    private mirror). No-op when the secret is absent.
  - The MaxMind download reads the account id + license key from **BuildKit secrets**
    (`mm_account_id`, `mm_license_key`) instead of build args, so the credentials never appear
    in build logs, image layers, or `docker history` — even if a step fails.
- **`.github/workflows/ci-build.yml`** — builds the image and exports it as a
  `docker load`-compatible tarball **artifact** (never pushed to a registry). Triggers on push
  to `develop`, on PRs, and via manual dispatch (with a platform choice).
- **`THIRD_PARTY_NOTICES.md`** — generated from `go.mod` via `just third-party-notices`
  (`go.elastic.co/go-licence-detector`, gated by `assets/licence/rules.json`'s license
  allowlist). `just third-party-notices-check` (wired into
  `.github/workflows/license-notice.yml`) fails CI if it's out of date with `go.mod`.
- **Inherited kentik workflows** (`publish-*`, `create-release`, `test-on-pr`,
  `clean-stale-issues`) — auto-triggers disabled by reducing each `on:` block to
  `workflow_dispatch:` only. Restore the original `on:` blocks (intact on `main` / in history)
  to re-enable.
- **`.dockerignore`** — excludes `.envrc` so local secrets never enter the build context.

## Secrets

**GitHub Actions** (set on this repo — used by `ci-build.yml`):

| secret | purpose |
|--------|---------|
| `MM_ACCOUNT_ID`   | MaxMind account ID (GeoLite2 download) |
| `MM_DOWNLOAD_KEY` | MaxMind license key |
| `SNMP_PROFILES_TOKEN` | fine-grained PAT, read-only Contents on `newrelic-forks/snmp-profiles` (mirror is public, so this is no longer strictly required, but the opt-in auth path stays wired in case that changes) |

**Local** (`.envrc`, gitignored, loaded by direnv):

- `MM_ACCOUNT_ID`, `MM_DOWNLOAD_KEY`

For the local snmp clone we reuse your `gh` token (`gh auth token`) rather than the PAT.

## CI build → downloadable image (recommended path)

Push to `develop`, or run **"CI Build (no push)"** manually from the Actions tab.
It compiles the Go binary (`make`), downloads the MaxMind DBs, clones the private snmp mirror
via the PAT, and assembles the image — **without pushing to any registry**. Instead it exports
the image as a `docker load`-compatible tarball and uploads it as a **build artifact**.

The exported tar is single-platform. On a manual run you pick the platform
(`linux/amd64` default, or `linux/arm64` — choose arm64 to `docker load` on Apple Silicon).
A `push`/PR run defaults to `linux/amd64`.

### Get the image onto a machine

1. Open the workflow run in the **Actions** tab and download the
   `ntranslate-image-<platform>-<version>` artifact (a zip).
2. Unzip it to get `ntranslate-image.tar`, then:

```bash
docker load -i ntranslate-image.tar
docker image ls | grep ntranslate                 # now visible locally
docker run --rm --entrypoint ktranslate ntranslate:ci -h          # smoke test (prints usage)
# inspect baked-in assets:
docker run --rm --entrypoint sh ntranslate:ci -c \
  'ls /etc/ktranslate/profiles | head; ls -la /etc/ktranslate/GeoLite2-*.mmdb'
```

Note: a `push:false` CI build keeps the image only on the runner (discarded at job end) —
the artifact export is what lets you retrieve and run it. This is also the way to get a
working image locally while the direct local build is blocked by the corporate TLS proxy.

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
  --secret id=mm_account_id,env=MM_ACCOUNT_ID \
  --secret id=mm_license_key,env=MM_DOWNLOAD_KEY \
  --build-arg KENTIK_KTRANSLATE_VERSION=local-test \
  --build-arg KENTIK_SNMP_PROFILE_REPO=https://github.com/newrelic-forks/snmp-profiles \
  -t ntranslate:local --load .
```

**Known blocker — corporate TLS interception.** On a network with a TLS-intercepting proxy
(e.g. Zscaler/Netskope), the in-build `curl` to MaxMind fails with
`SSL certificate ... self-signed certificate in certificate chain`, because the build
container doesn't trust the corporate root CA. Options: build off that network, or inject the
corporate root CA into the network-using build stages (`maxmind`, `snmp`, `build`) and run
`update-ca-certificates`. CI is unaffected.

## Security note — credentials are BuildKit secrets

Both the MaxMind creds and the snmp token are passed as BuildKit **secret mounts**, so their
values never land in build args, logs, image layers, or `docker history` — even on a failed
build. Keep it that way: do **not** reintroduce them as `--build-arg` (build args are expanded
into the printed `RUN` command, which leaks them when a step fails).
