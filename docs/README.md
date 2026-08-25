# Docs index

Working notes, investigation write-ups, and contributor reference for this fork. Most of
these (everything under "Investigations" below) describe an area that's been explored and
can be acted on, revised, or removed at any time — they're not fixed specs.

## Contributor reference

- [`CONTRIBUTING.md`](./CONTRIBUTING.md) — how to contribute to Kentik Labs projects
  (issue reporting, PR process).
- [`PLAYGROUND.md`](./PLAYGROUND.md) — what this fork is for: an internal investigation
  playground on top of upstream `kentik/ktranslate`, not wired up to publish anywhere.

## Investigations

- [`SINKS_REMOVAL_FEASIBILITY.md`](./SINKS_REMOVAL_FEASIBILITY.md) — feasibility analysis
  for removing every non-New Relic/OTel sink; also documents how to recover a removed sink
  via the `archive/pre-sink-removal` tag.
- [`DISCOVERY_PERFORMANCE_PLAN.md`](./DISCOVERY_PERFORMANCE_PLAN.md) — bottleneck analysis
  and remediation plan for slow SNMP discovery/polling.
- [`BENCHMARKING_PLAN.md`](./BENCHMARKING_PLAN.md) — the measurement layer for the above:
  how each proposed fix gets a before/after benchmark before being called done.
