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
  version "0.3.1"
  license "Apache-2.0"

  on_macos do
    on_arm do
      url "https://github.com/fulminate-io/knowledge-mcp/releases/download/v0.3.1/knowledge-darwin-arm64.tar.gz"
      sha256 "ba053a6160ec1cd3485b9f896eb73cba0b4f11238c03697fdf8cc2809d6b99df"

      resource "server" do
        url "https://github.com/fulminate-io/knowledge-mcp/releases/download/v0.3.1/knowledge-server-darwin-arm64.tar.gz"
        sha256 "07227be03feef0128c8a8894d527859a9e9320234ebfc34506aa57f35ba622af"
      end
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/fulminate-io/knowledge-mcp/releases/download/v0.3.1/knowledge-linux-arm64.tar.gz"
      sha256 "2cdbd309ed713a2a0c37901d685f7ee66a202dbfc59f7509c7026c1d9e59c917"

      resource "server" do
        url "https://github.com/fulminate-io/knowledge-mcp/releases/download/v0.3.1/knowledge-server-linux-arm64.tar.gz"
        sha256 "592414c99ae3bc5adeb4f3e2179e850303031a3955ec07c1c1ecb03603aabd86"
      end
    end
    on_intel do
      url "https://github.com/fulminate-io/knowledge-mcp/releases/download/v0.3.1/knowledge-linux-amd64.tar.gz"
      sha256 "948ec6ff7ffd0a9960303d846033885563267245a66efc7f670ed5b673f2f76c"

      resource "server" do
        url "https://github.com/fulminate-io/knowledge-mcp/releases/download/v0.3.1/knowledge-server-linux-amd64.tar.gz"
        sha256 "8489374fd160de06b3625cdb95abb0a697bd3c9e48e7048c29ef91820f6765e5"
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
