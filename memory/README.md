# PIE Memory Model v1

Memory lanes:
- memory/active/memory.ndjson = current unregistered working memory
- memory/coding/memory.ndjson = durable coding preferences
- memory/projects/<project>/memory.ndjson = registered project memory

Router rule:
If a project is registered and active, use project memory.
If no project is active or recognized, use active memory.
If message appears to belong to another registered project, ask before switching.
