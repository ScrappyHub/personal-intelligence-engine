# Packet Constitution v1 — Compliance checklist (Option A)

## Producer
- [ ] Write payload/** first
- [ ] Write manifest.json WITHOUT packet_id (canonical JSON bytes)
- [ ] Write signatures/** after payload+manifest (if used)
- [ ] Compute PacketId = SHA256(canonical_bytes(manifest-without-id))
- [ ] Write packet_id.txt
- [ ] Generate sha256sums.txt last over required files (EXCLUDING sha256sums.txt)
- [ ] Emit receipts last

## Verifier
- [ ] Do not mutate packet
- [ ] Recompute PacketId from manifest bytes and compare packet_id.txt
- [ ] Verify sha256sums against on-disk bytes
- [ ] Signature verify deterministic + trust-bundle based (if signatures present)

## Test vectors
- [ ] test_vectors include golden manifest bytes + PacketId + sha256sums + expected result
