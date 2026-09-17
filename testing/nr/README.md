# NR testing harness

Manual/local harness for running this fork's ktranslate against real SNMP
devices and a real New Relic account, used while iterating on
[NR-612348](https://new-relic.atlassian.net/browse/NR-612348) (identifying
new agent installs). Not part of CI -- this is for a developer running the
agent by hand and eyeballing (or, eventually, NRQL-querying) the result in
New Relic.

## One-time setup: secrets via secretspec

Two real secrets are needed -- a New Relic API key and the SNMP community
string for the devices being polled -- and neither should ever be typed into
a script, a config file, or this repo. [secretspec](https://secretspec.dev)
(`nix develop` already provides it, see `flake.nix`) keeps them in 1Password
instead:

```bash
secretspec config global init   # one-time: pick the `onepassword` provider
cd testing/nr
secretspec check                # confirms NEW_RELIC_API_KEY / SNMP_COMMUNITY are set
```

`secretspec check` will prompt you to store each value in 1Password if it
isn't there yet. From then on, run everything through `secretspec run --`
so the values are injected straight into the environment and never touch
disk:

```bash
secretspec run -- ./run-snmp-test.sh up --site bcn --cidr 203.0.113.0/24 --nr-account-id <id>
```

**Never** run a command that would print these values back out (`env`,
`printenv`, `set -x`, dumping `state/*/snmp.yaml`) in a shell anyone else --
human or agent -- can see.

## Running

```bash
secretspec run -- ./run-snmp-test.sh up --site <name> --cidr <cidr> --nr-account-id <id> \
    [--nr-region us_stage] [--image upstream|local] [--profiles-dir /path/to/snmp-profiles/profiles] \
    [--custom-attributes key=value[,key=value...]]
```

- `--image upstream` (default) pulls `kentik/ktranslate:v2`, the public
  upstream image. Anything else is used as-is as a local image reference,
  no pull attempted -- build one first with `./build-fork-image.sh`:

  ```bash
  ./build-fork-image.sh develop            # -> ntranslate:develop
  ./build-fork-image.sh main                # -> ntranslate:main
  ./build-fork-image.sh my-scratch-branch    # -> ntranslate:my-scratch-branch
  ```

  Then point `run-snmp-test.sh` at whichever one you're testing:
  `--image ntranslate:develop`, `--image ntranslate:main`, etc. Always know
  which one you're actually running -- it's easy to think you tested a fork
  change when the container is still running yesterday's image.

  `build-fork-image.sh` checks the given git ref out into a throwaway
  worktree and builds it there, so it never touches your current branch or
  working tree. It reuses `docs/PLAYGROUND.md`'s existing local-build
  secrets (`.envrc`'s `MM_ACCOUNT_ID`/`MM_DOWNLOAD_KEY`, `gh auth token`) --
  that's a separate, already-established mechanism from the `secretspec`
  ones above, kept that way on purpose.

  If that hits the corporate-TLS-interception blocker `docs/PLAYGROUND.md`
  already documents (MaxMind's `curl` failing with an SSL certificate
  error), use `fetch-ci-image.sh` instead -- it gets the same image built by
  `.github/workflows/ci-build.yml` in GitHub Actions, unaffected by your
  local network:

  ```bash
  ./fetch-ci-image.sh develop            # dispatches a fresh CI run, waits, -> ntranslate:develop
  ./fetch-ci-image.sh develop --latest    # skips the dispatch, grabs the latest successful run instead
  ```

  Only works for refs that already have `ci-build.yml` -- that's `develop`
  and anything branched from it today, **not** `main` (which stays a
  faithful copy of upstream `kentik/ktranslate`, with upstream's own
  workflows, not this fork's).
- `--profiles-dir` is optional: point it at a local clone of the private
  `snmp-profiles` mirror if you want profiles mounted in from outside the
  image.
- `--custom-attributes` passes straight through to `-nr_custom_attributes`
  ([NR-612348](https://new-relic.atlassian.net/browse/NR-612348)) -- stamps
  every metric batch this run sends with the given `key=value` pairs, e.g.
  `--custom-attributes install_id=my-test-run`, so you can tell it apart
  from any other ktranslate instance's data in NR (see "how do I know these
  are my metrics" -- this is the actual fix for that). Only understood by
  images built after that change landed (`ntranslate:nr-custom-attributes`
  or later); leave it unset against `--image upstream` or an older build --
  the flag doesn't exist there and the agent will reject it.
- The first `up` for a given `--site` renders `snmp-template.yaml` into
  `state/<site>/snmp.yaml` with your `--cidr` and the `SNMP_COMMUNITY`
  secret filled in, then discovers devices into that file. Subsequent `up`
  runs for the same site reuse that file instead of wiping discovered
  devices -- delete `state/<site>/snmp.yaml` yourself to force a fresh
  discovery.

Tear down:

```bash
./run-snmp-test.sh down --site <name>
```

## Everything under `state/` is gitignored, and must stay that way

`state/<site>/snmp.yaml` contains the resolved SNMP community string and
whatever real device inventory gets discovered (hostnames, IPs, engine
IDs). It is generated locally, gitignored (`.gitignore`), and must never be
committed, pasted into a PR, or handed to a tool that doesn't need it.

`snmp-template.yaml` itself, on the other hand, is generic and safe to
commit -- keep it that way. If you're tempted to hardcode a real CIDR or
community string into it "just for now," don't; that's exactly what the old
version of these scripts did, and it's why they got rewritten.
