# Homebrew formula for knowledge-server — the local graph server for Knowledge.
#
# The long-lived graph server (closed-source, garble-obfuscated). The
# `knowledge` daemon (the separate `knowledge` formula) connects to it on
# :15022 when you run fully local (not logged in to Fulminate Cloud) and for
# sync. Run it as its own `brew services` background service alongside
# `knowledge` — Homebrew is one service per formula, so this is a second
# formula with its own launchd job.
#
# Pre-built download (no Go toolchain needed): darwin-arm64, linux-amd64,
# linux-arm64. There is no darwin-amd64 (Intel) build.

class KnowledgeServer < Formula
  desc "Local graph server for Knowledge (the engineering OS for LLMs)"
  homepage "https://github.com/fulminate-io/knowledge-mcp"
  version "0.4.0"
  license "Apache-2.0"

  on_macos do
    on_arm do
      url "https://github.com/fulminate-io/knowledge-mcp/releases/download/v0.4.0/knowledge-server-darwin-arm64.tar.gz"
      sha256 "a5ff6d36a8367a4ee06adc68f45b3427dc590a51f812e0cde148e93d1eb4b68b"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/fulminate-io/knowledge-mcp/releases/download/v0.4.0/knowledge-server-linux-arm64.tar.gz"
      sha256 "6f0dc7e5a267e504c714b2f218e6de40e1b5595eb64e7a49bd22a991e97bfab5"
    end
    on_intel do
      url "https://github.com/fulminate-io/knowledge-mcp/releases/download/v0.4.0/knowledge-server-linux-amd64.tar.gz"
      sha256 "499c21ad1cd1a8b6c97a16ff481eb44e4dafa9eb27e3181d437623b32f27f90a"
    end
  end

  def install
    # The archive holds a single bare binary (no leading directory).
    bin.install "knowledge-server"
  end

  service do
    # Run the local graph server as a launchd-managed PER-USER service.
    # `brew services start knowledge-server`; the `knowledge` daemon connects
    # on :15022. Per-user LaunchAgent (no `require_root`) — do NOT `sudo`.
    run [opt_bin/"knowledge-server", "--port", "15022"]
    keep_alive true
    run_at_load true
    working_dir HOMEBREW_PREFIX
    log_path var/"log/knowledge-server.log"
    error_log_path var/"log/knowledge-server.log"
    environment_variables PATH: std_service_path_env
  end

  def caveats
    <<~EOS
      knowledge-server is the local graph server. Start it (as your user — do
      NOT use sudo) alongside the knowledge daemon:

        brew services start knowledge-server

      Logs: #{var}/log/knowledge-server.log

      Credentials live in the [credentials] section of ~/.knowledge/config
      (see the `knowledge` formula's caveats).
    EOS
  end

  test do
    # --version fast-exits with the embedded release version before binding
    # any port — deterministic, no network/port/stdin state.
    assert_match version.to_s, shell_output("#{bin}/knowledge-server --version 2>&1")
  end
end
