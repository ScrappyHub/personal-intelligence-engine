# PIE LAW v1

PIE is an instrument. Claims are only valid when backed by verifiable artifacts.

## Law 1 - Offline-first
PIE must not require cloud services to operate.

## Law 2 - Canonical bytes
Any hashed/signed JSON MUST be canonicalized (sorted keys, no whitespace, UTF-8 no BOM, LF).

## Law 3 - Content addressing
Model weights, prompts, outputs, and run records are identified by SHA-256 of canonical bytes.

## Law 4 - Append-only run ledger
Local run ledger is append-only NDJSON. Each entry includes prev_hash to prevent silent deletion/rewrite.

## Law 5 - NeverLost v1 identity
If signing is enabled, signatures MUST verify under derived allowed_signers with strict namespace enforcement.
