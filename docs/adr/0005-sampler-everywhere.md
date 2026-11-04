# ADR 0005 — Sampler primitive everywhere; expectation values computed in L3

- **Status:** Accepted
- **Date:** 2026-11-04

## Context
Providers differ in their estimator and mitigation features. Our own mitigation and QEC stages need raw counts and per-shot data.

## Decision
Every provider is driven through Sampler-style execution that returns raw counts or bitarrays. Measurement grouping happens in L1; expectation values, mitigation and decoding happen in L3.

## Consequences
- Data stays provider-neutral, and mitigation is ours, so it is comparable across providers.
- More circuits per job (measurement groups), and provider-side built-in mitigation goes unused.
