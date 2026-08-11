# PIE Memory Model v1

Memory lanes:
- memory/active/memory.ndjson = current unregistered working memory
- memory/coding/memory.ndjson = durable coding preferences
- memory/projects/<project>_<repo-hash>/memory.ndjson = project memory bound to one canonical repository path

Router rule:
If a project is registered and active, use coding memory plus project memory bound to that exact repository.
If no project is active or recognized, use active memory.
If message appears to belong to another registered project, ask before switching.

Memory behavior:
- records receive stable `mem_<sha256>` identifiers derived from lane, project, repo, and text
- exact duplicate accepts are no-ops
- forgetting appends a tombstone; it does not rewrite memory history
- malformed NDJSON fails context construction closed
- relevant records are ranked deterministically against the current user message
- policy mode `off` disables both memory writes and memory injection

Commands:
- `pie memory list`
- `pie memory search -Text "query"`
- `pie memory accept -Text "preference" -Lane coding`
- `pie memory forget -MemoryId mem_<sha256>`
