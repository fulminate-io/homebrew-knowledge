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
  version "0.1.2"
  license "Apache-2.0"

  on_macos do
    on_arm do
      url "https://github.com/fulminate-io/knowledge-mcp/releases/download/v#{version}/knowledge-darwin-arm64.tar.gz"
      sha256 "53e880a28612212160818128c3bea26ab5d6099ad94eaf2c818cd349f615fe01"

      resource "server" do
        url "https://github.com/fulminate-io/knowledge-mcp/releases/download/v#{version}/knowledge-server-darwin-arm64.tar.gz"
        sha256 "3898a06dea6798d72b836b078c519b3187774e9d9449b29f80f3b9aaa7c3f644"
      end
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/fulminate-io/knowledge-mcp/releases/download/v#{version}/knowledge-linux-arm64.tar.gz"
      sha256 "b715d5cd75448e839f9f9ddef7e69c8b751cbba7b0917493e1eb104b18b7802f"

      resource "server" do
        url "https://github.com/fulminate-io/knowledge-mcp/releases/download/v#{version}/knowledge-server-linux-arm64.tar.gz"
        sha256 "62ca762316b933b2ce1ea7936e4dc62003f7a9584e4b60177606f46ab0c440fc"
      end
    end
    on_intel do
      url "https://github.com/fulminate-io/knowledge-mcp/releases/download/v#{version}/knowledge-linux-amd64.tar.gz"
      sha256 "5aad87e24bdc716d53e71866100e369c9ca6337924babcefc52599f728c72dbc"

      resource "server" do
        url "https://github.com/fulminate-io/knowledge-mcp/releases/download/v#{version}/knowledge-server-linux-amd64.tar.gz"
        sha256 "f2ce65caa1138f7d658e078d256c0edb0e3f4a216a42de313c7ea5568a671994"
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
