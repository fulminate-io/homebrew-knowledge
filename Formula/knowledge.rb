# Homebrew formula for Knowledge — the engineering OS for LLMs.
#
# Ships two pre-built binaries from the GitHub release:
#   - knowledge         — the MCP stdio client; what .mcp.json points at.
#                         Provides start/stop/status + install subcommands.
#   - knowledge-server  — the long-lived TCP graph server (closed-source,
#                         garble-obfuscated). The launchd service block
#                         below runs it; manual lifecycle via `knowledge
#                         start/stop` also works.
#
# Both land in #{HOMEBREW_PREFIX}/bin side-by-side, so `knowledge`'s
# findServerBinary resolves `knowledge-server` via same-dir lookup.
#
# Pre-built download (no Go toolchain needed): the client tarball is the
# main `url`; the server tarball rides a per-platform `resource`. Only the
# release-pipeline targets are covered — darwin-arm64, linux-amd64,
# linux-arm64. There is no darwin-amd64 (Intel) build; brew reports the
# standard "no available download" on that platform.

class Knowledge < Formula
  desc "Engineering operating system for LLMs (MCP server + graph + reasoning)"
  homepage "https://github.com/fulminate-io/knowledge"
  version "0.1.3"
  license "Apache-2.0"

  on_macos do
    on_arm do
      url "https://github.com/fulminate-io/knowledge-mcp/releases/download/v0.1.3/knowledge-darwin-arm64.tar.gz"
      sha256 "739db46dd348010a320941bea3713b81ecfc61a83869d5e323a956c1cf8a338b"

      resource "server" do
        url "https://github.com/fulminate-io/knowledge-mcp/releases/download/v0.1.3/knowledge-server-darwin-arm64.tar.gz"
        sha256 "3f1dffaafc4974b209d786c83bf55fdbf12df01b560141a3997aa911fd10e17d"
      end
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/fulminate-io/knowledge-mcp/releases/download/v0.1.3/knowledge-linux-arm64.tar.gz"
      sha256 "73e684473eb1d6868576d0e3093eb779093dbcd1ff565b18c2eecc51cbdb42d8"

      resource "server" do
        url "https://github.com/fulminate-io/knowledge-mcp/releases/download/v0.1.3/knowledge-server-linux-arm64.tar.gz"
        sha256 "d5a171c21107c26abd7c8b8fdf027d45598c194827d9c356a73ab4b0b4b39412"
      end
    end
    on_intel do
      url "https://github.com/fulminate-io/knowledge-mcp/releases/download/v0.1.3/knowledge-linux-amd64.tar.gz"
      sha256 "52f2a6b9a23a0cd252611228116fd786b40c835519bc5d1be1575a3f4ad00284"

      resource "server" do
        url "https://github.com/fulminate-io/knowledge-mcp/releases/download/v0.1.3/knowledge-server-linux-amd64.tar.gz"
        sha256 "aff717f4e54e40cd14d92fdc48a02e9d9def1483ac40dd4f35d01d4aaac0a7b3"
      end
    end
  end

  def install
    # Client tarball is the main download; server tarball is the resource.
    # Each archive holds a single bare binary (no leading directory).
    bin.install "knowledge"
    resource("server").stage { bin.install "knowledge-server" }
  end

  service do
    # Run knowledge-server as a launchd-managed background service.
    # `brew services start knowledge` registers + starts; survives reboots.
    run [opt_bin/"knowledge-server", "--port", "15022"]
    keep_alive true
    run_at_load true
    working_dir HOMEBREW_PREFIX
    log_path var/"log/knowledge-server.log"
    error_log_path var/"log/knowledge-server.log"
    # Only PATH is pinned. We deliberately do NOT list LLM/backend creds
    # here: Homebrew filters the process env when evaluating the service
    # DSL, so an ENV.fetch(...) would write an EMPTY plist entry that
    # OVERRIDES whatever the user set via launchctl. Credentials reach the
    # server via ~/.knowledge/config (see caveats). PATH is a constant.
    environment_variables PATH: std_service_path_env
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

      The `knowledge` stdio client connects to the running server. If you'd
      rather drive lifecycle manually, skip `brew services` and use:

        knowledge start    # spawn the server
        knowledge status   # show pid + node/edge counts
        knowledge stop     # graceful shutdown

      Install the agent + skill catalog into your home directory:

        knowledge install-claude-assets

      Logs:
        brew services:    #{var}/log/knowledge-server.log
        knowledge start:  ~/.knowledge/server.log

      Credentials: a `brew services`-managed server runs under launchd,
      which does NOT read your shell rc files — put your keys in the
      [credentials] section of ~/.knowledge/config instead:

        [credentials]
        voyage_api_key = "..."   # vector embeddings + rerank (BM25 works without)
        linear_api_key = "..."   # Linear project/ticket backend (optional)
        # anthropic_api_key / openai_api_key / gemini_api_key — only needed
        # for dream workers with provider="anthropic"|"openai"|"gemini";
        # the default provider="claude-cli" auths via your `claude` login.

      chmod the file 600 if you store keys there. The starter config is
      written on first server run; edit it then `brew services restart knowledge`.

      Documentation: #{homepage}
    EOS
  end

  test do
    # The server's --version fast-exits with the embedded release version
    # before binding any port — deterministic, no network/port/stdin state.
    assert_match version.to_s, shell_output("#{bin}/knowledge-server --version 2>&1")

    # The client is a long-lived MCP stdio server (it reads stdin), so we
    # assert it installed as an executable rather than running it — running
    # it under the test harness can block on stdin.
    assert_predicate bin/"knowledge", :executable?
  end
end
