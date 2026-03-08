# PIE Packet Spec (PCv1 Option A) v1

- manifest.json excludes packet_id
- packet_id.txt = SHA-256(on-disk canonical manifest.json bytes)
- sha256sums.txt generated last over final bytes
- verifier is non-mutating
