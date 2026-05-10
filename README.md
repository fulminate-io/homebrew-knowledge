# homebrew-knowledge

Homebrew tap for [Knowledge](https://github.com/fulminate-io/knowledge) — the
engineering operating system for LLMs.

## Install

```bash
brew tap fulminate-io/knowledge
brew install --HEAD knowledge
```

`--HEAD` is required while v0.1.0 is in flight. Once the first stable
release lands, this becomes plain `brew install knowledge`.

## What this installs

Two binaries under `#{HOMEBREW_PREFIX}/bin`:

- `knowledge` — the MCP stdio client. Point your `.mcp.json` here.
- `knowledge-server` — the long-lived TCP graph server.

Plus a launchd service block so you can manage the server's lifecycle
through `brew services`:

```bash
brew services start knowledge   # auto-start on boot, survives reboots
brew services stop knowledge
brew services restart knowledge
```

If you'd rather drive lifecycle manually, skip `brew services` and use
the `knowledge` CLI directly:

```bash
knowledge start    # spawn the server
knowledge status   # show pid + node/edge counts
knowledge stop     # graceful shutdown
```

The stdio client also auto-spawns the server on first connection if no
server is running — so you can edit `.mcp.json` and your MCP host will
just work without any prior setup.

## MCP host config

```json
{
  "mcpServers": {
    "knowledge": {
      "command": "knowledge"
    }
  }
}
```

## License

The formula in this tap is Apache 2.0, matching the upstream project.

## Reporting issues

Bugs in the formula itself: open an issue here.
Bugs in Knowledge: <https://github.com/fulminate-io/knowledge/issues>.
