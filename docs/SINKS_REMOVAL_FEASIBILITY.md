# Removing non-New Relic / non-OTel sinks — feasibility analysis

Branch: `sinks-removal-investigation` (off `snmp-perf-benchmarking`). Written in response to
the question: how feasible is it to remove every sink that isn't New Relic or OTel, and how
much code comes out?

All line numbers below were read directly from the working tree at the time of writing.
Re-verify with `grep -n` before editing if the surrounding file has changed.

---

## 1. Executive summary

**Feasible, and cleanly isolated.** `pkg/sinks` is a well-factored plugin registry
(`pkg/sinks/sinks.go`) — each sink is its own subpackage behind a common `SinkImpl`
interface, self-registers its own CLI flags via a package `init()`, and (with two
exceptions, §4) has no reverse dependencies from the rest of the codebase. There are no
sink-specific unit tests to lose (only `pkg/sinks/nr` has one).

Removing every sink except `new_relic`, `new_relic_multi`, and `otel` deletes:

- **~2,150 lines** across 11 whole package directories (`pkg/sinks/{ddog,file,gcloud,
  gcppubsub,http,kafka,kentik,net,prom,s3,stdout}`)
- **~140 lines** of config structs/defaults in `config.go`
- **~280 lines** of flag-wiring `case` arms in `cmd/newrelic-network-agent/main.go`
- **~20 lines** of special-cased wiring in `pkg/cat/kkc.go` (§4)

**Total: ~2,600 lines of Go**, plus doc/example touch-ups (README flag help text,
`hack/{influxdb,snmp}/docker-compose.yml`).

It also fully drops two `go.mod` dependencies:

- `github.com/Shopify/sarama` (Kafka) — plus its transitive-only closure: `jcmturner/*`
  (Kerberos), `eapache/*`, `pierrec/lz4`, `klauspost/compress`, `DataDog/zstd`,
  `rcrowley/go-metrics`.
- `cloud.google.com/go/storage` (GCS, used only by the `gcloud` sink).

Two things worth flagging before doing this, both decisions rather than blockers — see §4
and §5.

---

## 2. What's actually there

`pkg/sinks/sinks.go` dispatches on a `Sink` string via `NewSink(...)`:

| Sink constant | Package | Lines | Keep? |
|---|---|---|---|
| `new_relic` | `nr` | 566 | **keep** |
| `new_relic_multi` | `nrmulti` | 130 | **keep** |
| `otel` | `otel` | 88 | **keep** |
| `kafka` | `kafka` | 358 | remove |
| `http` / `splunk` (alias) | `http` | 265 | remove |
| `s3` | `s3` | 347 | remove |
| `kentik` | `kentik` | 157 | remove |
| `prometheus` | `prom` | 191 | remove |
| `gcloud` | `gcloud` | 160 | remove |
| `file` | `file` | 263 | remove |
| `ddog` | `ddog` | 131 | remove |
| `net` | `net` | 115 | remove |
| `gcppubsub` | `gcppubsub` | 104 | remove |
| `stdout` | `stdout` | 54 | **decide** (§5) |
| `null` | inline in `sinks.go` | ~15 | trivial either way |

`SinkImpl` is a 4-method interface (`Init`, `Send`, `Close`, `HttpInfo`); every sink
implements only that, so deleting a package is a self-contained removal of one `case` arm
plus one import line in `sinks.go`.

Each removable sink registers its own flags in its own `init()`, e.g.
`pkg/sinks/kafka/kafa.go:47-52`, `pkg/sinks/s3/s3.go:42-47`,
`pkg/sinks/gcloud/gcloud.go:27-32`, `pkg/sinks/ddog/ddog.go:41-43`. Deleting the package
deletes the flag registration for free. What doesn't come for free is
`cmd/newrelic-network-agent/main.go`'s `applyFlags` (`main.go:238-`), which has one hand-written `case`
per flag name mapping it onto `cfg.<Sink>.<Field>` — that's real, reachable code (confirmed
via `flag.VisitAll`, not dead), and every arm for a removed sink needs deleting alongside
its config struct in `config.go`.

## 3. `config.go` and dependency surface

`config.go` defines one config struct per sink (`KafkaSinkConfig`, `S3SinkConfig`,
`GCloudSinkConfig`, `NetSinkConfig`, `FileSinkConfig`, `GCloudPubSubSinkConfig`,
`HTTPSinkConfig`, `KentikSinkConfig`, `DDogSinkConfig`, `PrometheusSinkConfig` —
`config.go:69-183`), each with a field in `Config` (`config.go:358-380`) and a default value
block in `DefaultConfig()` (`config.go:474-556`). `stdout`/`null` have no config struct.

Checked which `go.mod` dependencies are *exclusively* pulled in by a removable sink, vs.
shared with something that stays:

| Dependency | Also used by | Verdict |
|---|---|---|
| `github.com/Shopify/sarama` | nothing else | **fully removable** |
| `cloud.google.com/go/storage` | nothing else | **fully removable** |
| `cloud.google.com/go/pubsub` | `pkg/inputs/vpc/gcp/cp.go` (GCP VPC flow-log input) | **stays** — only the sink-side usage in `gcppubsub` goes |
| `github.com/aws/aws-sdk-go` | `pkg/inputs/vpc/aws/*`, `pkg/kt/aws.go` (AWS VPC flow-log input) | **stays** — only the sink-side usage in `s3` goes |
| `github.com/prometheus/client_golang` | `pkg/inputs/flow/flow.go`, `pkg/formats/prom` | **stays** — only the sink-side listener in `prom` goes |
| `github.com/DataDog/datadog-api-client-go/v2` | `pkg/formats/ddog` (not the sink) | **stays** — see §5, this is a *format*, not a *sink*, dependency |

So the "remove all non-NR/OTel sinks" scope gets you two clean dependency deletions
(sarama's whole closure, plus GCS), but AWS/GCP SDKs and the Prometheus client stick around
because other subsystems (VPC flow-log ingestion, internal metrics) need them regardless of
which sink ships the data out.

## 4. Two pieces of coupling to decide, not just delete

`pkg/cat/kkc.go` reaches into two "removable" sinks for functionality that isn't really
about picking a shipping destination:

- **`kentik` as a tee, independent of `--sinks`** (`kkc.go:219-228`): if
  `config.TeeFlow != ""`, a `kentik`-type sink is instantiated regardless of what's in the
  main `sinks` list, to forward a copy of flow to another ktranslate instance. Removing the
  `kentik` package breaks this unless the tee target is re-pointed at a different transport
  (e.g. `http`/`net` if kept, or a NR/OTel-flavored tee is built to replace it) — or the
  `tee_flow` feature is dropped too.
- **`s3` doubling as a `CloudObjectManager`** (`kkc.go:256-263`, `types.go:88`,
  `jchf.go:656-657`): if `config.S3Sink.Bucket` is set, the S3 sink is also wired up as a
  generic object store used by `getHar()` to fetch HAR files referenced by path (an
  HTTP-input enrichment feature). Removing `s3` drops HAR-file dereferencing unless another
  object store backs it.

Neither is large (~20 lines total), but both are *feature* decisions (drop `tee_flow`? drop
HAR dereferencing? or keep one non-NR/OTel sink alive specifically as infrastructure for
these?) rather than mechanical deletions. Nothing else in the codebase reaches into a
removable sink's internals — `pkg/api` (the stub Kentik device-management API used for SNMP
device bootstrapping) is a separate subsystem from the `kentik` *sink* and is unaffected by
this either way.

## 5. Two scope questions worth asking before cutting

1. **Is "sinks" the right unit, or does the team also want formats?** `--format` is a
   separate, independently-selectable axis (`json|flat_json|avro|netflow|influx|carbon|
   prometheus|new_relic|new_relic_metric|splunk|elasticsearch|kflow|ddog|otel|snmp|
   parquet`, `cmd/newrelic-network-agent/main.go:76`) and most non-NR/OTel formats
   (`pkg/formats/{avro,carbon,ddog,elasticsearch,influx,netflow,parquet,prom,redis,splunk}`,
   ~5,200 lines total) have no code-level tie to which sink ships them. If only sinks are
   removed, `--format=splunk` (etc.) becomes dead weight with nowhere sensible to go — it's
   the formats package, not the sinks package, that's carrying the 345k-line
   `datadog-api-client-go` dependency (`pkg/formats/ddog/ddog.go:16-17`), for example. A
   full cleanup of "everything non-NR/OTel" would eventually want to revisit formats too;
   that's a separate, larger piece of work from this sink removal and not scoped here.
2. **What's the new default sink?** `DefaultConfig()` (`config.go:425`) and the `--sinks`
   flag (`main.go:80`) both default to `stdout`, and the local dev compose files
   (`hack/influxdb/docker-compose.yml:38`, `hack/snmp/docker-compose.yml:20`) rely on that
   default for a no-external-dependency smoke test. `stdout` isn't NR/OTel, but it's also
   free (no network dependency, 54 lines, zero third-party deps) — worth explicitly deciding
   whether it stays as the dev/debug default or whether the default becomes `new_relic` and
   local testing switches to `otel`'s stdout exporter mode instead (`pkg/formats/otel`
   already supports an `otel.protocol=stdout` mode per `otel.go`'s flag help text).

## 6. Suggested next step

This doc is the analysis only — no sink code has been touched on this branch. If the team
wants to proceed, the mechanical part (delete 11 directories, prune `sinks.go`/`config.go`/
`main.go`, `go mod tidy`) is maybe half a day of work; the two judgment calls in §4 and the
two scope questions in §5 are the part that actually needs a decision before starting.

## 7. Recovering a removed sink later

The removal itself happened in a single commit, `99ff54b` ("refactor(sinks)!: remove
non-New Relic/OTel sinks"). Nothing here is a one-way door — every removed sink (`kafka`,
`ddog`, `file`, `gcloud`, `gcppubsub`, `kentik`, `net`, `prom`, plus the `splunk` alias and
`s3`-as-a-default-sink) is fully intact one commit earlier, and that commit is tagged
`archive/pre-sink-removal` (`cded527`) specifically so it doesn't need to be rediscovered by
digging through `git log`.

To bring one back:

- **See what it looked like:** `git show archive/pre-sink-removal:pkg/sinks/kafka/kafa.go`
  (swap the path for any other removed sink).
- **Restore just that sink's files:** `git checkout archive/pre-sink-removal -- pkg/sinks/kafka`,
  then re-add its `case` arm in `pkg/sinks/sinks.go`, its config struct + default block in
  `config.go`, and its flag-override `case` arms in `cmd/newrelic-network-agent/main.go` — diff
  `99ff54b` against `archive/pre-sink-removal` for the exact lines that came out for that
  sink.
- **Restore everything this commit removed:** `git revert 99ff54b` (this also brings back
  the `hack/prometheus` compose files and the `README`/`config.go` sections it touched).

Deliberately not doing this via commented-out code in the tree: a whole sink implementation
sitting inertly in comments would never get compile-checked, linted, or covered by CI, so it
would silently rot as `SinkImpl`, config structs, or logger signatures drift — and it adds
permanent noise for a "just in case." A tag against the exact pre-removal commit costs
nothing to maintain and is guaranteed to still be exactly correct whenever it's needed.
