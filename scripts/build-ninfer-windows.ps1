# Builds the Codex NInfer Windows package into dist/codex-ninfer-windows-x64.
#
# Usage (from the repository root):
#   powershell -ExecutionPolicy Bypass -File .\scripts\build-ninfer-windows.ps1
#
# Optional parameters:
#   -Profile release    (default: release; "debug" also works)
#   -OutDir <path>      (default: <repo root>\dist\codex-ninfer-windows-x64)
#   -NoBuild            only stage previously built binaries
#
# The script never writes outside the repository root.

[CmdletBinding()]
param(
    [ValidateSet("debug", "release")]
    [string]$Profile = "release",
    [string]$OutDir = "",
    [switch]$NoBuild
)

$ErrorActionPreference = "Stop"

# Resolve the repository root (two levels above scripts/).
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot
$codexRs = Join-Path $repoRoot "codex-rs"
if (-not (Test-Path (Join-Path $codexRs "Cargo.toml"))) {
    Write-Error "codex-rs/Cargo.toml not found; run this script from a full repository clone."
}
if (-not $OutDir) {
    $OutDir = Join-Path $repoRoot (Join-Path "dist" "codex-ninfer-windows-x64")
}

if ($env:PROCESSOR_ARCHITECTURE -ne "AMD64") {
    Write-Error "Expected an x64 Windows host (PROCESSOR_ARCHITECTURE=$env:PROCESSOR_ARCHITECTURE)."
}

$target = "x86_64-pc-windows-msvc"

if (-not $NoBuild) {
    # The toolchain is pinned in codex-rs/rust-toolchain.toml; rustup uses it.
    & cargo --version
    if ($LASTEXITCODE -ne 0) {
        Write-Error "cargo not found. Install Rust (rustup) with the MSVC toolchain."
    }

    Write-Host "==> Building binaries ($Profile, $target). This can take a while."
    $env:CARGO_TARGET_DIR = Join-Path $repoRoot "codex-rs/target"
    Push-Location $codexRs
    try {
        & cargo build --target $target --profile $Profile `
            --bin codex `
            --bin codex-windows-sandbox-setup `
            --bin codex-command-runner
    }
    finally {
        Pop-Location
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Error "cargo build failed."
    }
}

# Stage the package layout:
#   dist/codex-ninfer-windows-x64/
#     codex-ninfer.exe
#     codex-windows-sandbox-setup.exe
#     codex-command-runner.exe
#     README.txt
#     Install.cmd / Uninstall.cmd    easy installer (no toolchain needed)
$expectedBinaries = [ordered]@{
    "codex-ninfer.exe"                = (Join-Path $binDir "codex.exe")
    "codex-windows-sandbox-setup.exe" = (Join-Path $binDir "codex-windows-sandbox-setup.exe")
    "codex-command-runner.exe"        = (Join-Path $binDir "codex-command-runner.exe")
}

if (Test-Path $OutDir) {
    Remove-Item -Recurse -Force $OutDir
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

foreach ($dest in $expectedBinaries.Keys) {
    $src = $expectedBinaries[$dest]
    if (-not (Test-Path $src)) {
        Write-Error "Missing build output: $src (build first, or run with -NoBuild after building)"
    }
    Copy-Item $src (Join-Path $OutDir $dest)
}

$readmeLines = @(
    "Codex NInfer Windows package (unofficial Codex CLI fork)",
    "",
    "CONTENTS (keep all three executables in the SAME folder):",
    "  codex-ninfer.exe                 main Codex executable. The Windows",
    "                                   main thread stack is linked at 32 MiB,",
    "                                   which fixes interactive /resume stack",
    "                                   overflows on large session histories.",
    "  codex-windows-sandbox-setup.exe  Windows sandbox helper",
    "  codex-command-runner.exe         sandboxed command runner",
    "  README.txt                       this file",
    "  Install.cmd                      double-click to install (no Rust",
    "                                   Visual Studio or admin rights needed)",
    "  Uninstall.cmd                    double-click to uninstall",
    "",
    "EASIEST SETUP",
    "  Double-click Install.cmd. It copies the executables, writes the",
    "  starter config, and (on request) adds Codex NInfer to your PATH.",
    "  Open a new terminal, then run:",
    "",
    "      codex-ninfer",
    "",
    "MANUAL SETUP",
    "  1. Create a profile directory (the installer default):",
    "     set CODEX_HOME=%USERPROFILE%\.codex-ninfer",
    "     mkdir %CODEX_HOME%",
    "",
    "  2. Create %CODEX_HOME%\config.toml, for example:",
    "",
    '    "     model = "qwen3.8-27b"',
    '    "     model_provider = "ninfer"',
    '    "     model_reasoning_effort = "medium"',
    '    "     model_context_window = 262144"',
    '    "     model_auto_compact_token_limit = 200000"',
    '    "     web_search = "disabled"',
    '    "     approval_policy = "on-request"',
    '    "     sandbox_mode = "workspace-write"',
    "",
    '    "     [model_providers.ninfer]"',
    '    "     name = "NInfer"',
    '    "     base_url = "http://<NINFER_HOST>:8080/v1"   # your NInfer host"',
    '    "     wire_api = "responses"',
    '    "     requires_openai_auth = false"',
    "",
    "  3. Start Codex from the folder containing the three executables:",
    "     codex-ninfer.exe",
    "",
    "NOTES",
    "  - The qwen3.8-27b slug enables the 262144-token context window",
    "    automatically; no extra configuration is needed.",
    "  - web_search is disabled because NInfer has no native web_search",
    "    executor; MCP tools, shell, and apply_patch are unaffected.",
    "  - MCP servers are optional and not installed automatically. Add",
    "    your own under [mcp_servers.<name>] in config.toml; tools are",
    "    exposed to the model as mcp__<server>__<tool> calls.",
    "  - See README.md in the repository for full documentation and",
    "    troubleshooting.",
    "  - No API key is required for a LAN NInfer endpoint.",
    ""
)

# Also stage the installer files so the release ZIP can be installed
# by double-clicking Install.cmd (no Rust/toolchain needed on the user side).
$installerFiles = @("Install.cmd", "install-ninfer.ps1", "Uninstall.cmd")
foreach ($file in $installerFiles) {
    $src = Join-Path $repoRoot (Join-Path "scripts" (Join-Path "installer" $file))
    if (-not (Test-Path $src)) {
        Write-Warning "Installer file missing, skipping: $src"
    } else {
        Copy-Item $src (Join-Path $OutDir $file)
    }
}

Set-Content -Path (Join-Path $OutDir "README.txt") -Value $readmeLines -Encoding ascii

Write-Host ""
Write-Host "Package written to: $OutDir"
