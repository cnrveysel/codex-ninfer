# Codex CLI (unofficial fork) — NInfer + Qwen3.8-27B support for Windows

> **Unofficial fork.** This repository is an unofficial fork of
> [OpenAI Codex CLI](https://github.com/openai/codex), licensed under
> [Apache-2.0](LICENSE) by OpenAI. All upstream copyright and license
> notices are preserved. The additional commits in this fork add support
> for running Codex as a local coding agent backed by **NInfer** serving
> **Qwen3.8-27B** (OpenAI `/v1/responses` compatible) on Windows.
>
> Nothing here is endorsed by or affiliated with OpenAI.

## Purpose

OpenAI Codex CLI is designed to talk to OpenAI's hosted Responses API.
Local backends such as NInfer that expose an OpenAI-compatible `/v1/responses`
endpoint (e.g. with a locally served Qwen3.8-27B) are not natively understood
by upstream Codex. This fork makes that combination work out of the box on
Windows, including the Windows sandbox helpers and the `apply_patch` tool.

## What this fork changes (diff vs. upstream `openai/codex`)

| Area | Change |
| --- | --- |
| MCP namespace flattening | Providers without `type: "namespace"` tool support (e.g. NInfer) get MCP tools flattened to plain `mcp__<server>__<tool>` function tools. New optional `namespace_tools` provider flag (`false` = flatten; defaults to `requires_openai_auth`). |
| NInfer `call_tool` bridge | The `unreal` MCP server's `call_tool` schema exposes `arguments_json` (a JSON-object string) instead of a nested object, and the handler re-encodes it back to `arguments` before the MCP call. |
| Qwen3.8-27B model metadata | The slug `qwen3.8-27b` gets real metadata: 262144-token context window (100% effective), reasoning levels `none/low/medium/xhigh` (default `medium`), parallel tool calls enabled, no "unknown model" warning. |
| Reasoning handling | For `qwen3.8-27b` the client always sends a `reasoning` object (effort from config, summary disabled) even when the model doesn't advertise summary support, so NInfer receives the reasoning level the user picked. Reasoning items are stripped from the request `input` before sending. |
| `max_output_tokens` | New optional `max_output_tokens` field on the Responses API request. For NInfer + Qwen3.8-27B with `medium` reasoning it is set to `min(context_window - auto_compact_limit, 16384)`, keeping long-context prompts under the model's output limit. |
| `include` / `parallel_tool_calls` | `reasoning.encrypted_content` is no longer requested (local backends cannot produce it); `parallel_tool_calls` is forced `true` on the Responses request. |
| Custom `CODEX_HOME` | Config discovery now also skips the *default* `~/.codex` directory when walking project ancestors, so a custom `CODEX_HOME` no longer re-loads the default user config when the home folder is a project root. |
| Windows `apply_patch` | The `apply_patch` alias is now a **hard-linked (or copied) `apply_patch.exe`** instead of an `apply_patch.bat` shim. The `arg0` dispatcher routes on the executable file *stem*, which fixes multiline-patch and argument-quoting problems of the batch shim on Windows. |
| Windows sandbox helpers | Codex requires `codex-windows-sandbox-setup.exe` / `codex-command-runner.exe` next to the main binary for sandboxed shell execution; see `docs/ninfer-windows.md`. |
| Tests | Unit/integration coverage added for all of the above (`client_tests`, `registry_tests`, `spec_plan_tests`, `loader/tests`, `model_provider_info_tests`, `codex-api` client tests). |

The LM Studio build (`codex-lmstudio-v1.exe`) is a *separate* binary and is
not affected by these changes.

## Easy Windows install

For non-technical users, the GitHub Releases ZIP can be installed with
a double click — no Rust, Cargo, Git, or Visual Studio Build Tools
required:

1. Download the Windows ZIP from GitHub Releases.
2. Extract it to any folder (e.g. your Downloads folder).
3. Double-click `Install.cmd` inside the extracted folder.
4. Accept the default NInfer address (or type your NInfer host).
5. Open a new terminal.
6. Run `codex-ninfer`.

The installer copies the three executables to
`%LOCALAPPDATA%\CodexNInfer\bin`, writes a starter config to
`%USERPROFILE%\.codex-ninfer`, and (on request) adds the install
folder to your user PATH. No administrator rights are needed.
To remove the installation, double-click `Uninstall.cmd`.

Notes:

- The installer sets the `CODEX_HOME` user environment variable to the
  default profile `%USERPROFILE%\.codex-ninfer`, so a plain
  `codex-ninfer` launch uses the NInfer profile. Open a new terminal
  after installing.
- The generated config enables Qwen3.8-27B with `medium` reasoning
  (`model_reasoning_effort = "medium"`), a 262144-token context window
  and auto-compact at 200000 tokens, uses the NInfer provider without
  OpenAI auth, and sets `web_search = "disabled"` because NInfer does
  not provide a native `web_search` executor. Tools the fork supports,
  such as MCP tools, shell, and `apply_patch`, are not affected.
- MCP integrations are optional and are not installed automatically.
  Users can add their own MCP servers to the Codex NInfer config.
- To uninstall, double-click `Uninstall.cmd`. Removing the profile is
  optional (default: keep it). Running Codex processes can lock some
  profile temp files; in that case the uninstaller reports the files it
  could not remove and continues with the rest of the cleanup — close
  Codex and run Uninstall.cmd again to remove them.

## Building on Windows

Prerequisites: Rust stable (MSVC toolchain) and the Windows SDK. The
workspace builds with plain `cargo`:

```powershell
cd <path-to-repo>
cargo build --release --workspace
```

The three executables Codex needs on Windows **must sit in the same folder**:

```
C:\Users\<user>\bin\codex-ninfer\
├── codex-ninfer.exe                 # main binary (the `codex` entrypoint, renamed)
├── codex-windows-sandbox-setup.exe  # Windows sandbox helper
└── codex-command-runner.exe         # sandboxed command runner
```

Build all three from this workspace and place them in one folder; Codex's
`arg0` layer prepends that folder to `PATH` and creates the `apply_patch.exe`
alias (hard link, copy as fallback) there at startup.


### Build Windows package

After cloning the repository, build the three-binary Windows package
from the repository root with a single command:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-ninfer-windows.ps1
```

The script builds `codex` (with the forked 32 MiB Windows main-stack
linker fix applied automatically) plus the two sandbox helper
executables, then stages them in:

```
dist/codex-ninfer-windows-x64/
    codex-ninfer.exe
    codex-windows-sandbox-setup.exe
    codex-command-runner.exe
    README.txt
```

Keep all three `.exe` files in the same folder. Optional parameters:
`-Profile debug`, `-OutDir <path>`, `-NoBuild` (stage only). On
GitHub, the `ninfer-windows-build` workflow produces the same package
as the `codex-ninfer-windows-x64` build artifact.

## Configuration

Set `CODEX_HOME` to a dedicated profile directory, e.g.:

```powershell
$env:CODEX_HOME = "C:\Users\<user>\.codex-ninfer"
```

Example `CODEX_HOME\config.toml`:

```toml
model = "qwen3.8-27b"
model_provider = "ninfer"
reasoning_effort = "medium"   # none | low | medium | xhigh
approval_policy = "on-request"
sandbox_mode = "workspace-write"

[model_providers.ninfer]
name = "NInfer"
base_url = "http://<NINFER_HOST>:8080/v1"
wire_api = "responses"
# No API key is required for a LAN NInfer endpoint; set `api_key`
# only if your deployment enforces one.
```

Notes:

- `base_url` points at your NInfer host on the LAN (substitute the real
  host/IP of your NInfer server; port `8080` is a common default).
- The 262144-token context window is picked up from the model metadata
  automatically; no extra configuration is needed for 262K context.
- Reasoning `none` and `medium` are both supported; `medium` additionally
  caps output at 16K tokens (see above) and is the recommended setting
  for Qwen3.8-27B.
- With `reasoning_effort = "medium"` the request carries
  `max_output_tokens = min(context - compact limit, 16384)`.

## Using MCP tools

Any MCP server configured in `CODEX_HOME\config.toml` works:

```toml
[mcp_servers.myserver]
command = "C:\Users\<user>\tools\my-mcp-server.exe"
```

With the flatten patch, tools arrive at the model as
`mcp__myserver__toolname` function calls, which NInfer/Qwen handle
reliably. Tool-call to tool-result to continuation cycles work as usual.

## Test results (local RTX 4090, single machine)

Informational measurements taken on the author's machine (RTX 4090,
Qwen3.8-27B via NInfer). These are **not** guarantees and will vary
widely with hardware, model revision, and NInfer version:

| Configuration | End-to-end throughput |
| --- | --- |
| LM Studio + Codex | 51.6 tok/s |
| NInfer + Codex (this fork) | 77.8 tok/s |
| NInfer raw backend (decode, without Codex overhead) | ~139 tok/s |

## Troubleshooting

See [`docs/ninfer-windows.md`](docs/ninfer-windows.md) for the full
Windows troubleshooting guide (sandbox helpers, `apply_patch`, LAN
connectivity, context window behavior).

## License

Apache-2.0, (c) OpenAI and contributors — see `LICENSE` and `NOTICE`.

## Windows `/resume` stack overflow fix

Interactive `/resume` of large sessions crashed on Windows with

```text
thread 'main' (...) has overflowed its stack
```

(`STATUS_STACK_OVERFLOW`), while `RUST_MIN_STACK` did **not** fix it: that
environment variable only affects tokio worker threads created at runtime,
not the main thread that loads the session history.

This fork therefore raises the **main executable** stack reserve to 32 MiB
via the linker at build time (`/STACK:33554432` on MSVC, `--stack=33554432`
on the GNU toolchain). The rule lives in `codex-rs/cli/build.rs`, so it
applies automatically to the `codex` executable only — other workspace
binaries keep the workspace-wide 8 MiB setting.

Verified: an interactive `/resume` of a large old session opens in 1-2
seconds with this setting.

Manual fallback (if you build without the fork's `build.rs`):

```powershell
cargo rustc -p codex-cli --bin codex -- -C link-arg=/STACK:33554432
```
