# Homebrew formula for Knowledge — the engineering OS for LLMs.
#
# Ships two binaries:
#   - knowledge         — the MCP stdio client; this is what .mcp.json
#                         points at. Auto-spawns the server on first
#                         use; provides start/stop/status subcommands.
#   - knowledge-server  — the long-lived TCP graph server. The launchd
#                         service block below runs this binary; users
#                         who'd rather drive lifecycle manually can
#                         skip `brew services` and use `knowledge
#                         start/stop` from any terminal.
#
# Install layout: both binaries land in #{HOMEBREW_PREFIX}/bin (so
# they're side-by-side and `knowledge`'s findServerBinary picks
# `knowledge-server` via os.Executable + same-dir lookup before
# falling through to $PATH).
#
# Build is from source. CGO is required (tree-sitter parser bindings).
# Go is the only build dep — the C compiler comes from Xcode CLT
# which Homebrew already requires.

class Knowledge < Formula
  desc "Engineering operating system for LLMs (MCP server + graph + reasoning)"
  homepage "https://github.com/fulminate-io/knowledge"
  license "Apache-2.0"

  # Until we tag a release + stand up GoReleaser, install from main.
  # `brew install --HEAD knowledge` is the canonical install command.
  # When v0.1.0 lands, add a `url` + `sha256` stable block above
  # this `head` and remove the `--HEAD`-only requirement.
  head "https://github.com/fulminate-io/knowledge.git", branch: "main"

  depends_on "go" => :build

  def install
    ENV["CGO_ENABLED"] = "1"

    # Mirror .claude/{agents,skills} into the embed location used by
    # cmd/knowledge/internal/claudeassets — required before go build
    # so the `knowledge install-claude-assets` subcommand embeds the
    # latest project agents/skills. The directories are gitignored
    # so a fresh clone has no stale embed copies. Script is idempotent.
    system "./scripts/sync-claude-assets.sh"

    # ldflags carries the version string the binaries report via
    # `--version` (when that flag lands; harmless otherwise).
    ldflags = %W[
      -s -w
      -X main.version=#{version}
    ]

    system "go", "build",
      *std_go_args(ldflags: ldflags, output: bin/"knowledge"),
      "./cmd/knowledge"

    system "go", "build",
      *std_go_args(ldflags: ldflags, output: bin/"knowledge-server"),
      "./cmd/knowledge-server"
  end

  service do
    # Run knowledge-server as a launchd-managed background service.
    # `brew services start knowledge` registers + starts; survives
    # reboots via `keep_alive` and `run_at_load`.
    run [opt_bin/"knowledge-server", "--port", "15022"]
    keep_alive true
    run_at_load true
    working_dir HOMEBREW_PREFIX
    log_path var/"log/knowledge-server.log"
    error_log_path var/"log/knowledge-server.log"
  end

  def caveats
    <<~EOS
      To run the graph server in the background (survives reboots):

        brew services start knowledge

      Then add to your project's .mcp.json:

        {
          "mcpServers": {
            "knowledge": {
              "command": "knowledge"
            }
          }
        }

      The `knowledge` stdio client connects to the running server. If
      you'd rather drive lifecycle manually, skip `brew services` and
      use:

        knowledge start    # spawn the server
        knowledge status   # show pid + node/edge counts
        knowledge stop     # graceful shutdown

      Logs:
        brew services:    #{var}/log/knowledge-server.log
        knowledge start:  ~/.knowledge/server.log

      Optional: set VOYAGE_API_KEY to enable hybrid vector search.
      BM25 search works without it.

      Documentation: #{homepage}
    EOS
  end

  test do
    # Both binaries must be runnable + report their flag set.
    assert_match "knowledge", shell_output("#{bin}/knowledge -h 2>&1", 2)
    assert_match "knowledge", shell_output("#{bin}/knowledge-server -h 2>&1", 2)

    # The status subcommand should report "not running" with exit 1
    # when no server is up — verifies the lifecycle dispatch wires
    # up cleanly without needing a real server in the test sandbox.
    assert_match "not running", shell_output("#{bin}/knowledge status 2>&1", 1)
  end
end
