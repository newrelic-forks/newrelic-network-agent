# Removing `github.com/DataDog/zstd` — feasibility analysis

Branch: `zstd-removal-feasibility` (off `develop`). Written in response to the question: now
that the Datadog and Parquet formats are gone (see the two PRs preceding this one), what's
left pulling in `github.com/DataDog/zstd`, and how feasible is it to remove?

All facts below were confirmed directly — either by reading source (this repo's and the
relevant dependencies', pulled from the local module cache) or by actually running
`go mod tidy` against a worktree with the Datadog/Splunk/Parquet formats removed, not
inferred from `go.mod`/`go.sum` alone. Re-verify with `go mod why` before acting on this if
the dependency graph has moved since.

---

## 1. Executive summary

**`DataDog/zstd` survives the Datadog-format removal, and it isn't a version-bump problem —
it can only go away by removing `github.com/honeycombio/libhoney-go` (Honeycomb telemetry)
entirely.** Confirmed empirically: with `pkg/formats/ddog`, `pkg/formats/splunk`, and
`pkg/formats/parquet` all removed and `go mod tidy` run for real, `go.mod` still has
`github.com/DataDog/zstd v1.5.0 // indirect`, unchanged. `go mod why -m github.com/DataDog/zstd`
against that state gives:

```
github.com/kentik/ktranslate/pkg/eggs/baseserver
github.com/honeycombio/libhoney-go
github.com/honeycombio/libhoney-go/transmission
github.com/honeycombio/libhoney-go/transmission.test
github.com/DataDog/zstd
```

So the sole remaining requirer is `libhoney-go`, reached through `pkg/eggs/baseserver` (used
by every `ktranslate` service via `BaseServer`'s optional Honeycomb hook).

## 2. How libhoney-go actually uses it

`github.com/DataDog/zstd` is **not** used by libhoney's production compression path. Reading
the actual source (pulled from the module cache) for both the version pinned here, `v1.15.6`,
and the current release, `v1.27.1`:

- `transmission/transmission.go` (no build tag, compiled into every consumer) imports
  `github.com/klauspost/compress/zstd` — a pure-Go zstd implementation — and that's what
  actually compresses the JSON/msgpack batch payload libhoney POSTs to Honeycomb's
  `/1/batch/<dataset>` endpoint (`Content-Encoding: zstd`).
- `github.com/DataDog/zstd` appears **only** in `transmission/transmission_test.go`, with an
  explicit comment: *"Use a different zstd library from the implementation, for more
  convincing testing."* It's there purely so the test suite can independently decode what the
  production `klauspost`-based encoder produced, and to benchmark the two implementations
  against each other. Same pattern, same comment, in both `v1.15.6` and `v1.27.1` — it's not
  a stray leftover about to be cleaned up upstream, it's been stable across the whole release
  history.

This is exactly why it survives `go mod tidy` here even though `ktranslate`'s own build never
executes a line of `DataDog/zstd` code: Go's module graph accounts for a dependency's own
test-file imports of packages the importer (us) also uses in production
(`libhoney-go/transmission` is imported for real by libhoney's root package). The requirement
is a property of the `libhoney-go` module's own `go.mod`, not of anything in this repo — no
version bump of libhoney-go removes it, because every release checked, `v1.15.6` through
`v1.27.1`, keeps `require github.com/DataDog/zstd` in its own `go.mod`.

Note also: nothing in this repo's own `libhoney.Config{}` construction
(`pkg/eggs/baseserver/baseserver.go`) sets `Transmission` or `DisableCompression` — so
libhoney's default sender, and its default `klauspost/compress/zstd` compression, is what
actually runs whenever Honeycomb telemetry is enabled (`-olly_dataset`/`-olly_write_key` set).

## 3. Blast radius of removing libhoney-go / `pkg/eggs/olly`

Repo-wide, exactly 4 files touch this:

- **`pkg/eggs/olly/events.go`** — a thin wrapper package around `libhoney-go`
  (`Builder`/`Event`/`Init`/`Close`/`QuickC`/`PrepareC`/`AddContext`/`AddUuid`/`AddErr`).
  Deleting it means deleting the wrapper wholesale.
- **`pkg/eggs/baseserver/baseserver.go`** — the only consumer of `pkg/eggs/olly` anywhere in
  the repo. Exported surface that would need to change:
  - `BaseServerConfiguration.OllyWriteKey` / `.OllyDataset` (exported config fields)
  - `BaseServer.OllyBuilder()`, `.InitOlly()`, `.FinishOlly()` (exported methods)
  - the `-olly_dataset` / `-olly_write_key` CLI flags registered in its `init()`
  - two `olly.QuickC(bs, olly.Op("baseserver.start"|"baseserver.stop"))` calls bracketing
    `Run()` — the only two events this path ever actually emits
- **`config.go`** — `ServerConfig.OllyDataset`/`OllyWriteKey` fields and their `""` defaults.
- **`cmd/ktranslate/main.go`** — the flag-override `case "olly_dataset"`/`"olly_write_key"`
  arms that copy CLI/env values into `cfg.Server.Olly*`, plus the `NewBaseServer()` call that
  copies those into `BaseServerConfiguration`.

So removal is a small, single-owner change (4 files, one package deleted) but **not a pure
dependency edit** — it removes exported config fields, exported methods, and two CLI flags,
which is a real (if narrow) behavior/API change to `BaseServer`, not something `go mod tidy`
alone can do.

**How central this is today:** the telemetry is disabled by default
(`OllyDataset`/`OllyWriteKey` both default to `""`, and `InitOlly()` explicitly short-circuits
with `"olly: disabled"` when either is empty — no network I/O happens unless an operator sets
both). It's also not woven into the actual data path: no format, sink, or input package
touches `olly` at all — the only two events ever emitted are a start-of-run and end-of-run
beacon on `BaseServer` itself. Reporting this as an observation, not a recommendation: this
reads as a lifecycle heartbeat that happens to require an opt-in flag pair, not as
pervasive instrumentation.

## 4. Alternatives considered

- **A newer libhoney-go release** doesn't help — checked `v1.27.1` (current) directly, its
  `go.mod` still requires `github.com/DataDog/zstd v1.5.7`, same test-only usage pattern.
- **libhoney-go "v2"** (git tags `v2.0.0`, `v2.1.0`) is not a usable option: the module was
  never renamed to `.../libhoney-go/v2` as Go's semantic-import-versioning rules require, so
  `go get`/`go list -m -versions` can't resolve those tags at all — confirmed by fetching
  `v2.1.0`'s `go.mod` directly (still `module github.com/honeycombio/libhoney-go`, no `/v2`)
  and by libhoney's own `CHANGELOG.md`, which says outright: *"There were several v2 releases
  that were unusable because they were incomplete according to Go's semantic versioning
  strategy."* And even that unusable v2.1.0 still requires `DataDog/zstd v1.5.0` anyway.
- **The real alternative is dropping libhoney-go for the OpenTelemetry Go SDK** (an OTLP
  exporter pointed at Honeycomb's OTLP ingest endpoint instead of the classic `/1/batch` API)
  — this is Honeycomb's currently-recommended integration path for new Go instrumentation
  (their Beelines, the older auto-instrumentation layer built on libhoney, reached end of life
  in 2025 and are archived). This is not a drop-in swap: different wire protocol, and a
  different API shape (spans/traces vs. libhoney's flat event-batching model), so it would be
  a rewrite of `pkg/eggs/olly`'s two call sites' worth of logic, not a dependency bump.

## 5. Suggested next step

Feasible, in the sense that the blast radius is small and fully mapped above — but it's a
behavior change to `BaseServer`'s public surface, not a mechanical deletion like the
Datadog/Splunk/Parquet formats were. Whether to actually do it is a product decision, not a
mechanical one:

- If the team doesn't use the Honeycomb telemetry (no one sets `-olly_dataset`/
  `-olly_write_key` in any deployment), removing `pkg/eggs/olly` and the four touch points in
  §3 is a clean, low-risk deletion that finally drops `DataDog/zstd`.
- If it *is* in use somewhere, replacing it with an OTel-based exporter is the only path that
  both keeps the telemetry and drops the dependency — and that's real, separately-scoped work
  (new exporter wiring, not a deletion), not something to bundle into this pass.

This doc doesn't make that call — it's the input for whoever does.
