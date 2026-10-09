# PIE Encrypted Workspace Boundary v1

Status: design and release-blocker proposal

## Current Guarantee

Exported `.piebak` session archives use authenticated encryption. Interactive passphrases are read
from stdin. Workbench messages, session goals, and direct run prompts are also handed to child
processes through stdin rather than process arguments.

These controls protect transport between local PIE processes and encrypted exports. They do not
make the live workspace fully encrypted at rest.

## Remaining Plaintext Boundary

PIE currently keeps active conversations, prompts, memory records, goals, model output, run
artifacts, and transaction journals as plaintext files under the local runtime root. Temporary
backup staging can also contain plaintext while an archive is being assembled or verified.

Claiming that PIE is fully encrypted before those stores change would be incorrect.

## Required Design

1. Introduce a versioned encrypted state envelope using AES-256-GCM with a unique nonce per record.
2. Use a random workspace data-encryption key and wrap it with either Windows DPAPI or a
   passphrase-derived key. A portable recovery key must be explicit and optional.
3. Encrypt conversation turns, prompts, memory, session metadata, run input/output, transaction
   staged content, and backup staging before writing to disk.
4. Keep indexes privacy-minimal. Any searchable index must contain opaque identifiers or keyed
   hashes, never plaintext excerpts.
5. Support crash-safe key rotation and schema migration with rollback evidence.
6. Zero sensitive buffers where the runtime permits, use restrictive NTFS ACLs, and delete
   plaintext temporary files in `finally` blocks.
7. Add negative tests for wrong keys, swapped ciphertext, nonce reuse, truncated tags, rollback,
   process kill, and recovery after an interrupted rotation.

## Release Rule

Until this design is implemented and independently tested, product surfaces must say "encrypted
session exports" rather than "fully encrypted" or "encrypted workspace."
