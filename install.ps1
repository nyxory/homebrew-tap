# Nyxory CLI installer for Windows.
#
# This script is the canonical PowerShell installer. It is meant to be
# served from the public release repo (`nyxory/homebrew-tap`):
#
#   powershell -ExecutionPolicy Bypass -c "irm https://nyxory.com/install.ps1 | iex"
#
# It auto-detects the architecture, fetches the latest release zip from
# `nyxory/homebrew-tap`, verifies the SHA-256 checksum against the
# goreleaser-published `checksums.txt`, installs nyx.exe to a per-user
# directory, and adds that directory to the user PATH. When run in an
# interactive console it then chains straight into `nyx login` and
# `nyx setup` so one pasted command takes a fresh machine all the way to
# wired-up AI clients.
#
# The source of truth lives in `nyxory/cli` under `release/install.ps1`.
# A push to main that touches this file triggers
# `.github/workflows/mirror-install.yml`, which mirrors it to the root
# of `nyxory/homebrew-tap` (where the URL above serves from).
#
# `irm | iex` cannot pass parameters, so everything is also settable via
# environment variables:
#
#   NYX_VERSION       Install a specific tag (e.g. v0.6.0). Default: latest.
#   NYX_INSTALL_DIR   Install directory. Default: %LOCALAPPDATA%\Programs\nyx
#   NYX_INSTALL_ONLY  Set (any non-empty value) to skip the login/setup chain.
#   NO_COLOR          Disable colored output.
#
# Works on Windows PowerShell 5.1 and PowerShell 7+.

param(
    [string]$Version = $env:NYX_VERSION,
    [string]$InstallDir = $env:NYX_INSTALL_DIR
)

$ErrorActionPreference = 'Stop'
# The progress bar makes Invoke-WebRequest ~10x slower on Windows
# PowerShell 5.1 (the host the documented one-liner always launches).
$ProgressPreference = 'SilentlyContinue'

$Repo = 'nyxory/homebrew-tap'

# Windows PowerShell 5.1 defaults to TLS 1.0/1.1 on older builds; GitHub
# requires 1.2+. PowerShell 7 ignores this (always modern TLS).
if ($PSVersionTable.PSVersion.Major -lt 6) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

# Write-Host -ForegroundColor goes through the console API, not ANSI —
# safe on every host including legacy conhost. Only NO_COLOR opts out.
$UseColor = -not $env:NO_COLOR

function Write-Step([string]$Message) {
    # Plain ASCII on purpose: Windows PowerShell 5.1's default codepage
    # mangles box-drawing/braille, so no wordmark and no spinner here.
    if ($UseColor) {
        Write-Host '==> ' -ForegroundColor Green -NoNewline
        Write-Host $Message
    } else {
        Write-Host "==> $Message"
    }
}

function Write-Note([string]$Message) {
    if ($UseColor) {
        Write-Host $Message -ForegroundColor DarkGray
    } else {
        Write-Host $Message
    }
}

# Output strings stay pure ASCII: the downloaded-file path on PS 5.1
# reads this as ANSI and would mangle anything fancier.
if ($UseColor) {
    Write-Host ''
    Write-Host 'NYXORY' -ForegroundColor Green -NoNewline
    Write-Host ' - the nyxory deployment platform'
    Write-Host ''
} else {
    Write-Host ''
    Write-Host 'NYXORY - the nyxory deployment platform'
    Write-Host ''
}

# --- platform detection ------------------------------------------------------

# PROCESSOR_ARCHITEW6432 is set when a 32-bit PowerShell runs on a
# 64-bit OS — prefer it so we still install the right binary.
$rawArch = $env:PROCESSOR_ARCHITEW6432
if (-not $rawArch) { $rawArch = $env:PROCESSOR_ARCHITECTURE }
switch ($rawArch) {
    'AMD64' { $Arch = 'amd64' }
    'ARM64' { $Arch = 'arm64' }
    default {
        throw "unsupported architecture: $rawArch (need AMD64 or ARM64)"
    }
}

# --- resolve version ---------------------------------------------------------

if (-not $Version) {
    Write-Step 'Resolving latest release'
    # Anonymous GitHub API call — public repo, 60 req/h per IP is plenty.
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ 'User-Agent' = 'nyx-install-ps1' }
    $Version = $release.tag_name
    if (-not $Version) {
        throw "could not resolve latest release from github.com/$Repo - check that the repo has a published release"
    }
}
# Tags are always v-prefixed; tolerate NYX_VERSION=0.6.0.
if ($Version -notmatch '^v') { $Version = "v$Version" }

$Asset = "nyx-$Version-windows-$Arch.zip"
$AssetUrl = "https://github.com/$Repo/releases/download/$Version/$Asset"
$ChecksumsUrl = "https://github.com/$Repo/releases/download/$Version/checksums.txt"

# --- resolve install dir -----------------------------------------------------

if (-not $InstallDir) {
    # Per-user convention on Windows; no admin rights needed.
    $InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\nyx'
}
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

# --- download + verify + install ---------------------------------------------

$Tmp = Join-Path ([IO.Path]::GetTempPath()) ("nyx-install-" + [IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null

try {
    Write-Step "Downloading $Asset ($Version)"
    $zipPath = Join-Path $Tmp $Asset
    Invoke-WebRequest -Uri $AssetUrl -OutFile $zipPath -UseBasicParsing

    Write-Step 'Verifying checksum'
    $sumsPath = Join-Path $Tmp 'checksums.txt'
    Invoke-WebRequest -Uri $ChecksumsUrl -OutFile $sumsPath -UseBasicParsing
    $expectedLine = Get-Content $sumsPath | Where-Object { $_ -match [regex]::Escape($Asset) } | Select-Object -First 1
    if (-not $expectedLine) {
        throw "checksums.txt has no entry for $Asset"
    }
    $expected = ($expectedLine -split '\s+')[0].ToLower()
    $actual = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToLower()
    if ($expected -ne $actual) {
        throw "checksum mismatch for ${Asset}: expected $expected, got $actual"
    }

    Write-Step 'Extracting'
    $extractDir = Join-Path $Tmp 'extracted'
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
    # goreleaser zips are flat (nyx.exe at the root), but stay robust
    # against a future wrap_in_directory like install.sh does.
    $exe = Get-ChildItem -Path $extractDir -Filter 'nyx.exe' -Recurse | Select-Object -First 1
    if (-not $exe) {
        throw "extracted archive does not contain nyx.exe (looked under $extractDir)"
    }

    Write-Step "Installing to $InstallDir\nyx.exe"
    $target = Join-Path $InstallDir 'nyx.exe'
    Copy-Item -Path $exe.FullName -Destination $target -Force
    # Strip the Mark-of-the-Web so SmartScreen doesn't block first run.
    Unblock-File -Path $target -ErrorAction SilentlyContinue
} finally {
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}

# --- PATH (user scope, idempotent) ---------------------------------------------

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $userPath) { $userPath = '' }
$onPath = ($userPath -split ';' | Where-Object { $_.TrimEnd('\') -eq $InstallDir.TrimEnd('\') }).Count -gt 0
if (-not $onPath) {
    $newPath = if ($userPath) { "$userPath;$InstallDir" } else { $InstallDir }
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    Write-Note "added $InstallDir to your user PATH (new terminals pick it up automatically)"
}
# Make nyx available in THIS session too.
if (($env:Path -split ';') -notcontains $InstallDir) {
    $env:Path = "$env:Path;$InstallDir"
}

Write-Host ''
if ($UseColor) {
    Write-Host 'OK ' -ForegroundColor Green -NoNewline
    Write-Host "nyx $Version installed to $InstallDir\nyx.exe"
} else {
    Write-Host "OK nyx $Version installed to $InstallDir\nyx.exe"
}
Write-Host ''

# --- first-run chain -----------------------------------------------------------
# One pasted command end-to-end: sign in (browser OAuth, no stdin
# needed) and wire every detected AI client via `nyx setup`. Skipped
# when NYX_INSTALL_ONLY is set, in CI, or when there's no interactive
# console to drive it from. Older pinned versions without `nyx setup`
# fall back to printed next steps.
#
# Probe notes: `setup --help` (NOT `help setup` — cobra exits 0 with
# "Unknown help topic" for the latter, so it can't detect absence). The
# try/catch matters on PS <= 7.1: with EAP=Stop, redirected native
# stderr becomes a terminating NativeCommandError there. And no `exit`
# anywhere in this block — under a bare `irm | iex` that would close
# the user's terminal session.

$nyx = Join-Path $InstallDir 'nyx.exe'
$hasSetup = $false
try {
    & $nyx setup --help *> $null
    $hasSetup = ($LASTEXITCODE -eq 0)
} catch { }
$interactive = -not ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected -or $env:CI)

if ($hasSetup -and $interactive -and -not $env:NYX_INSTALL_ONLY) {
    Write-Step 'Signing in'
    $loginOk = $false
    try {
        & $nyx login
        $loginOk = ($LASTEXITCODE -eq 0)
    } catch { }
    if ($loginOk) {
        Write-Step 'Wiring your AI clients'
        # Marks this run as the chained installer path in the install
        # funnel (vs a hand-typed `nyx setup`).
        $env:NYX_SETUP_SOURCE = 'installer'
        & $nyx setup --all
        if ($LASTEXITCODE -ne 0) {
            Write-Host 'setup did not complete - re-run anytime with: nyx setup' -ForegroundColor Yellow
        }
    } else {
        Write-Host 'login did not complete - finish later with: nyx login; nyx setup' -ForegroundColor Yellow
    }
} else {
    Write-Host '  Next:'
    Write-Host '    nyx login          # sign in (defaults to the prod endpoint)'
    if ($hasSetup) {
        Write-Host '    nyx setup          # wire your AI clients (Claude Code, Codex, Cursor, VS Code)'
    } else {
        Write-Host '    nyx claude install # wire your agent (also: nyx cursor / codex install)'
    }
    Write-Host '    nyx --help         # everything else'
}
