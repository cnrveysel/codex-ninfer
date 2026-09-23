# NInfer on Windows — troubleshooting and setup notes

Companion to `README-NINFER.md` in the repository root.

## Layout

Keep all three Windows binaries in one folder and launch the main one:

```
C:\Users\<user>\bin\codex-ninfer\
├── codex-ninfer.exe
├── codex-windows-sandbox-setup.exe
└── codex-command-runner.exe
```

If sandboxed shell execution fails, the first thing to check is that the
two helper executables are present *next to* `codex-ninfer.exe`. Codex
locates them relative to the main binary, not on `PATH`.

## `apply_patch.exe` on Windows

This fork no longer writes an `apply_patch.bat` shim. Instead, at startup
the `arg0` layer creates `apply_patch.exe` in the binary folder as a
**hard link** to the main executable (with a plain file copy as fallback).
The dispatcher routes on the executable name without extension, so the
`apply_patch` alias reaches the patch code path directly.

Why: the batch shim broke multiline patch arguments on Windows (quoting,
CRLF, and `%` characters in patch content), which made `apply_patch` tool
calls fail or mangle the patch.

If the alias is missing or stale (for example after replacing the binary),
delete `apply_patch.exe` in the binary folder once and restart Codex; it is
recreated automatically. Do this while Codex is not running.

## NInfer server

- Endpoint: `http://<NINFER_HOST>:8080/v1` (adjust host/port to your setup).
- The model must be served under the slug `qwen3.8-27b` (or add your own
  `model_info` entry) so the fork's metadata patch applies.
- The server must expose the OpenAI-compatible `/v1/responses` endpoint
  with streaming; chat-completions-only endpoints are not supported.
- No API key is needed for a LAN deployment; if your NInfer build enforces
  auth, set `api_key` under `[model_providers.ninfer]`.

## Context window (262K)

- `qwen3.8-27b` metadata declares `context_window = 262144` at 100%
  effective percent, so Codex uses the full window.
- Auto-compact triggers near the limit; when `reasoning_effort = "medium"`,
  `max_output_tokens` is set to `min(context - compact limit, 16384)`, so
  near-full contexts still leave room for output.
- If the model stops mid-tool-call on very long sessions, lower
  `reasoning_effort` to `none` (removes the output cap) or start a new
  session.

## Reasoning

- `reasoning_effort = "none"` sends a `reasoning` object with `none`
  effort; `"medium"` (the default for this model) sends medium.
- Summary is always disabled for this model (local backends cannot
  re-attach encrypted reasoning content, so it is not requested).
- Reasoning items from previous turns are stripped before each request,
  which keeps NInfer-side state simple.

## Sandbox

- `sandbox_mode = "workspace-write"` restricts writes to the working
  directory; use `approval_policy = "on-request"` so escalated commands
  ask you explicitly.
- The sandbox user account and credential state are created by
  `codex-windows-sandbox-setup.exe` on first use; if sandbox startup
  errors mention missing users or logon failures, re-run setup with
  elevated privileges once — do not hand-edit the credential state.

## Common symptoms

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `apply_patch` tool fails on multiline patches | stale/missing `apply_patch.exe` alias | delete alias, restart Codex |
| MCP tool call errors like "unknown tool" | provider using namespace wrapper | ensure `namespace_tools` is unset/false for the provider (default for non-OpenAI providers) |
| Model emits truncated JSON in tool args | output cap hit | raise `max_output_tokens` headroom by lowering context usage, or set reasoning `none` |
| Config seems ignored with custom `CODEX_HOME` | default `~/.codex` picked up via project-ancestor walk | this fork skips the default `~/.codex` even for custom `CODEX_HOME`; make sure you run the forked binary |
| Connection refused to NInfer | host/port wrong, firewall | check `base_url`, LAN firewall, NInfer listening on `0.0.0.0` if remote |

## Privacy

Never commit: profile config files (`config.toml` under any `CODEX_HOME`),
API keys, LAN host addresses, model file paths, or sandbox credential
state. Keep them out of the repository.

## `/resume` stack overflow

Interactive `/resume` of a large session can crash on Windows with
`thread 'main' has overflowed its stack`. The stock 8 MiB main-thread
stack (set workspace-wide in `codex-rs/.cargo/config.toml`) is not enough
for large session histories, and `RUST_MIN_STACK` does **not** help because
it only sizes runtime-spawned tokio worker threads, not `main`'s thread.

This fork fixes it by linking the `codex` executable with a 32 MiB main
stack reserve (MSVC `/STACK:33554432`, GNU `--stack=33554432`) via
`codex-rs/cli/build.rs`. Any binary you build from this repository already
includes the fix. If you are on a custom build pipeline, apply it manually:

```powershell
cargo rustc -p codex-cli --bin codex -- -C link-arg=/STACK:33554432
```
