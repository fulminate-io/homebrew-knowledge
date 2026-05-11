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
    # launchd does NOT source the user's login shell, so anything in
    # ~/.zprofile / ~/.zshenv is invisible to the service. Capture every
    # credential knowledge-server reads from the environment of whoever
    # runs `brew services start` (i.e. the user's login shell) and bake
    # them into the generated plist. Empty fallback = feature disabled
    # (no error). Brew regenerates the plist from this block on every
    # `brew services restart` / `brew upgrade`, so this is the durable
    # mechanism — not a hand-edit of ~/Library/LaunchAgents/*.plist.
    #   - LINEAR_API_KEY:                       Linear project/ticket backend
    #   - VOYAGE_API_KEY:                       binary-vector embeddings + rerank
    #   - ANTHROPIC_API_KEY / OPENAI_API_KEY /  HTTP LLM providers
    #     GEMINI_API_KEY                        (provider = "anthropic"|"openai"|"gemini")
    # Forwarding ANTHROPIC_API_KEY is SAFE even though the default
    # config uses provider="claude-cli": the claudecli provider strips
    # ANTHROPIC_API_KEY from the `claude` subprocess env before exec, so
    # the CLI always auths via the user's login (subscription), never
    # paid-API billing — regardless of what's in this env. Same for the
    # codexcli provider and OPENAI_API_KEY.
    environment_variables(
      PATH:              std_service_path_env,
      LINEAR_API_KEY:    ENV.fetch("LINEAR_API_KEY", ""),
      VOYAGE_API_KEY:    ENV.fetch("VOYAGE_API_KEY", ""),
      ANTHROPIC_API_KEY: ENV.fetch("ANTHROPIC_API_KEY", ""),
      OPENAI_API_KEY:    ENV.fetch("OPENAI_API_KEY", ""),
      GEMINI_API_KEY:    ENV.fetch("GEMINI_API_KEY", ""),
    )
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

      Credentials: `brew services start knowledge` captures these from
      the environment of the shell you run it in (so export them in
      ~/.zprofile / ~/.zshenv first, then start the service):
        VOYAGE_API_KEY     hybrid vector search + rerank (BM25 works without)
        LINEAR_API_KEY     Linear project/ticket backend (optional)
        ANTHROPIC_API_KEY  only if you set provider="anthropic" in ~/.knowledge/config;
        OPENAI_API_KEY     the default provider="claude-cli" needs none of these
        GEMINI_API_KEY     — it auths via your `claude` CLI login.
      After changing which keys are exported, run `brew services restart
      knowledge` to regenerate the launchd plist.

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
