# Codex NInfer Windows installer / uninstaller.
#
# Install mode (default):
#   Copies the three Codex NInfer executables (which must sit next to this
#   script in the release ZIP) to %LOCALAPPDATA%\CodexNInfer\bin, writes a
#   starter CODEX_HOME config, persists the CODEX_HOME user environment
#   variable, and optionally adds the install folder to the user PATH.
#   No administrator rights, Rust, Cargo, or Visual Studio are required.
#
#   MCP servers are not installed automatically; users can add their own
#   MCP servers to the generated config later.
#
# Uninstall mode:
#   & install-ninfer.ps1 -Uninstall
#   Removes the installed binaries, the user PATH entry (if present), the
#   user CODEX_HOME variable (only if it points at this profile), and, on
#   request, the %USERPROFILE%\.codex-ninfer profile. Profile removal is
#   best-effort: files locked by a running Codex process are reported and
#   the rest of the uninstall continues. No process is ever killed.

[CmdletBinding()]
param(
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$host.UI.RawUI.WindowTitle = "Codex NInfer Installer"

$packageDir = $PSScriptRoot
$installRoot = Join-Path $env:LOCALAPPDATA "CodexNInfer"
$installDir = Join-Path $installRoot "bin"
$codeHome = Join-Path $env:USERPROFILE ".codex-ninfer"
$defaultEndpoint = "http://127.0.0.1:8080/v1"
$binaries = @("codex-ninfer.exe", "codex-windows-sandbox-setup.exe", "codex-command-runner.exe")

function Write-Step([string]$text) {
    Write-Host ""
    Write-Host $text -ForegroundColor Cyan
}

function Remove-InstallDir([string]$path) {
    if (Test-Path $path) {
        Remove-Item -Recurse -Force $path
        Write-Host "  Removed $path"
    } else {
        Write-Host "  Nothing to remove at $path"
    }
}

function Remove-ProfileDirBestEffort([string]$path) {
    # Best-effort removal for the profile directory: running Codex windows can
    # lock temp files (for example .codex-ninfer\tmp\arg0\...\apply_patch.exe).
    # Report the failure and let the rest of the uninstall continue.
    if (-not (Test-Path $path)) {
        Write-Host "  Nothing to remove at $path"
        return
    }
    try {
        Remove-Item -Recurse -Force $path
        Write-Host "  Removed $path"
    }
    catch {
        Write-Host "  Some profile files could not be removed: $($_.Exception.Message)"
        Write-Host "  They are probably locked by a running Codex NInfer process."
        Write-Host "  Close all Codex NInfer windows and run Uninstall.cmd again"
        Write-Host "  to remove the remaining profile files."
    }
}

function Remove-PathEntry([string]$folder) {
    $current = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not $current) {
        Write-Host "  User PATH is empty; nothing to remove."
        return
    }
    $parts = @($current -split ';' | Where-Object { $_ })
    $keep = @($parts | Where-Object { $_.TrimEnd('\') -ne $folder })
    if ($keep.Count -lt $parts.Count) {
        [Environment]::SetEnvironmentVariable("Path", ($keep -join ';'), "User")
        Write-Host "  Removed the install folder from your user PATH."
    } else {
        Write-Host "  No PATH entry found; nothing to remove."
    }
}

if ($Uninstall) {
    Write-Host "==============================================="
    Write-Host "         Codex NInfer Uninstaller"
    Write-Host "==============================================="

    Write-Step "[1/2] Removing installed binaries..."
    Remove-InstallDir $installDir
    $parent = Split-Path -Parent $installDir
    if ((Test-Path $parent) -and -not (Get-ChildItem $parent -Force)) {
        Remove-Item -Force $parent
        Write-Host "  Removed empty folder $parent"
    }

    Write-Step "[2/2] Cleaning up PATH, CODEX_HOME and (optionally) your profile..."
    Remove-PathEntry $installDir

    # Only clear the user CODEX_HOME when it points at this installer
    # profile; never touch a value that points somewhere else.
    $userCodeHome = [Environment]::GetEnvironmentVariable("CODEX_HOME", "User")
    if ($userCodeHome) {
        if ($userCodeHome.Trim().TrimEnd('\') -ieq $codeHome.Trim().TrimEnd('\')) {
            [Environment]::SetEnvironmentVariable("CODEX_HOME", $null, "User")
            Write-Host "  Removed user CODEX_HOME (it pointed at $codeHome)."
        } else {
            Write-Host "  Kept user CODEX_HOME ($userCodeHome) because it points elsewhere."
        }
    }

    Write-Host ""
    $answer = Read-Host "Also remove $codeHome (configuration and session data)? [y/N]"
    if ($answer -match '^[yY]') {
        Remove-ProfileDirBestEffort $codeHome
    } else {
        Write-Host "  Kept $codeHome (your configuration and session data are untouched)."
    }

    Write-Host ""
    Write-Host "  Uninstall finished."
    Write-Host "  Note: PATH and environment changes apply to new terminal windows."
    return
}

Write-Host "==============================================="
Write-Host "        Codex NInfer Windows Installer"
Write-Host "==============================================="

# --- [1/4] Install binaries -----------------------------------------------
Write-Step "[1/4] Installing binaries..."
foreach ($binary in $binaries) {
    $source = Join-Path $packageDir $binary
    if (-not (Test-Path $source)) {
        throw "Missing $binary in the release package. Extract the full ZIP and re-run Install.cmd."
    }
}
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
foreach ($binary in $binaries) {
    Copy-Item (Join-Path $packageDir $binary) (Join-Path $installDir $binary) -Force
    Write-Host "  $binary"
}
Write-Host "  All three binaries are installed in the same folder: $installDir"

# --- [2/4] Configure CODEX_HOME --------------------------------------------
Write-Step "[2/4] Configuring CODEX_HOME..."
Write-Host "  Default location: $codeHome (press Enter to accept)"
$codeHomeInput = Read-Host "  CODEX_HOME"
if (-not $codeHomeInput) { $codeHomeInput = $codeHome }
$codeHome = $codeHomeInput.Trim()
New-Item -ItemType Directory -Force -Path $codeHome | Out-Null
$configPath = Join-Path $codeHome "config.toml"

# Persist CODEX_HOME for the user so plain codex-ninfer uses this profile.
$env:CODEX_HOME = $codeHome
$existingCodeHome = [Environment]::GetEnvironmentVariable("CODEX_HOME", "User")
if ($existingCodeHome) {
    Write-Host "  Existing CODEX_HOME detected: $existingCodeHome"
    $answer = Read-Host "  Use $codeHome for Codex NInfer? [Y/n]"
    if ($answer -notmatch '^[nN]') {
        [Environment]::SetEnvironmentVariable("CODEX_HOME", $codeHome, "User")
        Write-Host "  User CODEX_HOME set to: $codeHome"
    } else {
        Write-Host "  Kept your existing CODEX_HOME value."
    }
} else {
    [Environment]::SetEnvironmentVariable("CODEX_HOME", $codeHome, "User")
    Write-Host "  User CODEX_HOME set to: $codeHome"
}

# --- [3/4] Configure NInfer -------------------------------------------------
Write-Step "[3/4] Configuring NInfer..."
Write-Host "  Default endpoint: $defaultEndpoint (press Enter to accept)"
$endpoint = Read-Host "  NInfer endpoint"
if (-not $endpoint) { $endpoint = $defaultEndpoint }
$endpoint = $endpoint.Trim()
if ($endpoint -notmatch '^https?://') { $endpoint = "http://$endpoint" }

$writeConfig = $true
if (Test-Path $configPath) {
    Write-Host "  Found existing config at $configPath"
    $answer = Read-Host "  Overwrite it? [y/N]"
    $writeConfig = ($answer -match '^[yY]')
}

if ($writeConfig) {
    $configLines = @(
        "# Codex NInfer configuration (generated by the installer)"
        'model = "qwen3.8-27b"'
        'model_provider = "ninfer"'
        ""
        '# "medium" reasoning for Qwen3.8-27B on NInfer'
        'model_reasoning_effort = "medium"'
        'model_context_window = 262144'
        'model_auto_compact_token_limit = 200000'
        ""
        '# NInfer has no native web_search executor'
        'web_search = "disabled"'
        ""
        'approval_policy = "on-request"'
        'sandbox_mode = "workspace-write"'
        ""
        "[model_providers.ninfer]"
        'name = "NInfer"'
        "base_url = `"$endpoint`""
        'wire_api = "responses"'
        'requires_openai_auth = false'
        ""
        "# MCP servers are optional and are not installed automatically."
        "# Add your own under [mcp_servers.<name>] if you want them."
    )
    Set-Content -Path $configPath -Value $configLines -Encoding ascii
    Write-Host "  Wrote $configPath"
} else {
    Write-Host "  Kept your existing config."
}

# --- [4/4] Finishing ---------------------------------------------------------
Write-Step "[4/4] Finishing installation..."

$existingUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathParts = @()
if ($existingUserPath) { $pathParts = $existingUserPath -split ';' | Where-Object { $_ } }
$alreadyInPath = @($pathParts | Where-Object { $_.TrimEnd('\') -ieq $installDir })
if ($alreadyInPath.Count -gt 0) {
    Write-Host "  PATH already includes the install folder."
} else {
    $answer = Read-Host "Add Codex NInfer to your user PATH? [Y/n]"
    if ($answer -notmatch '^[nN]') {
        if ($existingUserPath) {
            [Environment]::SetEnvironmentVariable("Path", ($existingUserPath.TrimEnd(';') + ";" + $installDir), "User")
        } else {
            [Environment]::SetEnvironmentVariable("Path", $installDir, "User")
        }
        Write-Host "  User PATH updated."
    } else {
        Write-Host "  PATH left unchanged."
    }
}

Write-Host ""
Write-Host "===============================================" -ForegroundColor Green
Write-Host "  Installation complete!" -ForegroundColor Green
Write-Host "==============================================="
Write-Host ""
Write-Host "  Binaries    : $installDir"
Write-Host "  CODEX_HOME  : $codeHome"
Write-Host "  Config      : $configPath"
Write-Host ""
Write-Host "  CODEX_HOME is configured. Open a new terminal before"
Write-Host "  running codex-ninfer (environment changes only apply to"
Write-Host "  new terminal windows)."
Write-Host ""
Write-Host "  In the new terminal, run:"
Write-Host ""
Write-Host "      codex-ninfer"
Write-Host ""
Write-Host "  To start Codex right now, run this instead:"
Write-Host ""
Write-Host "      $installDir\codex-ninfer.exe"
