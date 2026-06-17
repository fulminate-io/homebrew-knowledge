# Homebrew formula for Knowledge — the engineering OS for LLMs (client + daemon).
#
# Ships the `knowledge` binary: the CLI + the shared MCP daemon (`knowledge
# serve`). The launchd service below runs the daemon (:15023). The local graph
# server is a SEPARATE formula (`knowledge-server`, pulled in via depends_on)
# with its own `brew services` lifecycle — Homebrew supports one service per
# formula, so the two long-lived processes are two formulae:
#
#   brew services start knowledge-server   # local graph server   (:15022)
#   brew services start knowledge          # shared MCP daemon     (:15023)
#
# Pre-built download (no Go toolchain needed): darwin-arm64, linux-amd64,
# linux-arm64. There is no darwin-amd64 (Intel) build.

class Knowledge < Formula
  desc "Engineering operating system for LLMs (MCP client + shared daemon)"
  homepage "https://github.com/fulminate-io/knowledge-mcp"
  version "0.4.3"
  license "Apache-2.0"

  depends_on "fulminate-io/knowledge/knowledge-server"

  on_macos do
    on_arm do
      url "https://github.com/fulminate-io/knowledge-mcp/releases/download/v0.4.3/knowledge-darwin-arm64.tar.gz"
      sha256 "70ab72416f2d8d1095b5230f57d7fcb2d2da8a7833773d6622008380cdfd18c9"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/fulminate-io/knowledge-mcp/releases/download/v0.4.3/knowledge-linux-arm64.tar.gz"
      sha256 "17b65dac73bbcff2332a48349c71af1c57e8686c5518918cb92424d6fe18b07b"
    end
    on_intel do
      url "https://github.com/fulminate-io/knowledge-mcp/releases/download/v0.4.3/knowledge-linux-amd64.tar.gz"
      sha256 "440e26707cb6ff8ff1c9fd853a2ca47fa6b27ad99277f83b1a9b1a8413925ea9"
    end
  end

  def install
    # The archive holds a single bare binary (no leading directory).
    bin.install "knowledge"
  end

  service do
    # Run the shared MCP daemon (`knowledge serve`) as a launchd-managed
    # PER-USER service. `brew services start knowledge` registers + starts it;
    # editors connect at http://127.0.0.1:15023/mcp (port is FIXED — the
    # install-*-assets subcommands hardcode that URL). Per-user LaunchAgent
    # (no `require_root`): a root LaunchDaemon runs in a global context that
    # CANNOT read your login keychain, so Fulminate Cloud auth would silently
    # break — do NOT `sudo brew services start`.
    run [opt_bin/"knowledge", "serve", "--http-port", "15023",
         "--log-level", "info", "--log-file", var/"log/knowledge-daemon.log"]
    keep_alive true
    run_at_load true
    working_dir HOMEBREW_PREFIX
    log_path var/"log/knowledge-daemon.log"
    error_log_path var/"log/knowledge-daemon.log"
    # Only PATH is pinned. We deliberately do NOT list LLM/backend creds here:
    # Homebrew filters the process env when evaluating the service DSL, so an
    # ENV.fetch(...) would write an EMPTY plist entry that OVERRIDES whatever
    # the user set via launchctl. Credentials reach the pipeline via
    # ~/.knowledge/config (see caveats). PATH is a constant.
    environment_variables PATH: std_service_path_env
  end

  def caveats
    <<~EOS
      Start BOTH services (as your user — do NOT use sudo):

        brew services start knowledge-server   # local graph server (:15022)
        brew services start knowledge          # shared MCP daemon  (:15023)

      (sudo installs a root LaunchDaemon that can't read your login keychain,
      which breaks Fulminate Cloud auth.)

      Register the daemon with your editor(s) + install the agent/skill catalog:

        knowledge install-claude-assets    # Claude Code
        knowledge install-codex-assets     # Codex

      These point the editor at the daemon (http://127.0.0.1:15023/mcp); no
      manual .mcp.json entry is needed.

      For Fulminate Cloud, log in once (opens a browser):

        knowledge login

      The daemon reads the token from your login keychain. Without `knowledge
      login` it runs fully local against knowledge-server.

      Logs:  #{var}/log/knowledge-daemon.log

      Credentials: launchd does NOT read your shell rc files — put pipeline
      keys in the [credentials] section of ~/.knowledge/config:

        [credentials]
        voyage_api_key = "..."   # vector embeddings + rerank (BM25 works without)
        linear_api_key = "..."   # Linear project/ticket backend (optional)
        # anthropic_api_key / openai_api_key / gemini_api_key — only needed for
        # dream workers with provider="anthropic"|"openai"|"gemini"; the default
        # provider="claude-cli" auths via your `claude` login.

      Documentation: #{homepage}
    EOS
  end

  test do
    # The binary is a long-lived process (daemon/CLI); assert it installed as
    # an executable rather than running it (running can block on stdin/port).
    assert_predicate bin/"knowledge", :executable?
  end
end
