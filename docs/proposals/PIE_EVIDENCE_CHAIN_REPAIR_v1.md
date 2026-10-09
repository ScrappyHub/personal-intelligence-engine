# PIE Evidence Chain Repair v1

Status: implementation proposal

## Problem

The state-integrity freeze could ignore untracked source files and could record a dirty source tree
without refusing the freeze. The aggregate engine gate also reported green when required real-engine
positive checks were inconclusive. That made the resulting release claim stronger than its evidence.

The historical Tier-0 freeze remains valid only for the deterministic stub packet pipeline it
actually exercised. It is not evidence that a real model generated the sealed output.

## Implemented Direction

- A state-integrity freeze requires a clean source tree, including untracked source files.
- Generated proofs, test vectors, runtime state, and the transient memory lock are excluded from the
  source-clean check.
- `-SkipVerify` cannot produce a state-integrity freeze.
- Engine verification declares which engines are required. PIE's release gate requires Ollama.
- A required engine must complete its positive real-generation check before the aggregate can emit
  its green token.
- Optional engine absence is recorded as inconclusive and never represented as tested.

## Compatibility

No historical proof is rewritten. Existing receipt fields remain present; new receipts add required
engine and certification fields. Consumers must treat `certified` and `green` as false whenever a
required check is inconclusive.

## Follow-up

Real run packets need an additive provenance record that independently binds backend identity,
model identity, persona, effective prompt, generation parameters, ledger record, and output bytes.
