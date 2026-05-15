<#
.SYNOPSIS
    deepclaude — Use Claude Code with DeepSeek V4 Pro or other cheap backends.

.USAGE
    deepclaude                      # DeepSeek V4 Pro (default)
    deepclaude --backend or         # OpenRouter (cheapest)
    deepclaude --backend fw         # Fireworks AI (fastest)
    deepclaude --backend al         # DashScope (Alibaba Qwen)
    deepclaude --backend anthropic  # Normal Claude Code
    deepclaude --remote             # Remote control + DeepSeek (browser URL)
    deepclaude --remote -b or       # Remote control + OpenRouter
    deepclaude --status             # Show keys and backends
    deepclaude --cost               # Pricing comparison
    deepclaude --benchmark          # Latency test
#>

param(
    [Alias("b")]
    [string]$Backend,
    [Alias("r")]
    [switch]$Remote,
    [switch]$Status,
    [Alias("l")]
    [switch]$List,
    [switch]$Cost,
    [switch]$Benchmark,
    [switch]$Help,
    [Alias("s")]
    [string]$Switch,
    [string]$Port
)

$ErrorActionPreference = "Stop"

# Load .env file if present
$envFile = Join-Path $PSScriptRoot ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $_ = $_.Trim()
        if ($_ -and $_ -notmatch '^#') {
            $key, $value = $_ -split '=', 2
            [System.Environment]::SetEnvironmentVariable($key.Trim(), $value.Trim(), "Process")
        }
    }
}

if (-not $Backend -and -not $Switch -and -not $Status -and -not $List -and -not $Cost -and -not $Benchmark -and -not $Help) {
    $Backend = if ($env:CHEAPCLAUDE_DEFAULT_BACKEND) { $env:CHEAPCLAUDE_DEFAULT_BACKEND } else { "ds" }
}

# --- Switch ---
if ($Switch) {
    $proxyUrl = if ($Port) { "http://127.0.0.1:$Port" } elseif ($env:ANTHROPIC_BASE_URL) { $env:ANTHROPIC_BASE_URL } else { "http://127.0.0.1:3200" }
    $backendMap = @{ ds="deepseek"; deepseek="deepseek"; or="openrouter"; openrouter="openrouter"; fw="fireworks"; fireworks="fireworks"; al="dashscope"; dashscope="dashscope"; km="kimi"; kimi="kimi"; mm="mimo"; mimo="mimo"; um="umans"; umans="umans"; anthropic="anthropic" }
    $targetBackend = $backendMap[$Switch.ToLower()]
    if (-not $targetBackend) { Write-Host "ERROR: Unknown backend '$Switch'. Use: ds, or, fw, al, km, mm, anthropic" -ForegroundColor Red; exit 1 }
    $body = "backend=$targetBackend"
    $headers = @{ "content-type" = "application/x-www-form-urlencoded" }
    try {
        $resp = Invoke-RestMethod -Uri "$proxyUrl/_proxy/mode" -Method POST -Headers $headers -Body $body
        Write-Host "  Switched: $($resp.previous) -> $($resp.mode)" -ForegroundColor Green
    } catch {
        Write-Host "  Proxy not running at $proxyUrl" -ForegroundColor Red; exit 1
    }
    exit 0
}

# --- Config ---
$DeepSeekKey = if ($env:DEEPSEEK_API_KEY) { $env:DEEPSEEK_API_KEY } else {
    [Environment]::GetEnvironmentVariable("DEEPSEEK_API_KEY", "User")
}
$OpenRouterKey = if ($env:OPENROUTER_API_KEY) { $env:OPENROUTER_API_KEY } else {
    [Environment]::GetEnvironmentVariable("OPENROUTER_API_KEY", "User")
}
$FireworksKey = if ($env:FIREWORKS_API_KEY) { $env:FIREWORKS_API_KEY } else {
    [Environment]::GetEnvironmentVariable("FIREWORKS_API_KEY", "User")
}
$DashScopeKey = if ($env:DASHSCOPE_API_KEY) { $env:DASHSCOPE_API_KEY } else {
    [Environment]::GetEnvironmentVariable("DASHSCOPE_API_KEY", "User")
}
$KimiKey = if ($env:KIMI_API_KEY) { $env:KIMI_API_KEY } else {
    [Environment]::GetEnvironmentVariable("KIMI_API_KEY", "User")
}
$MimoKey = if ($env:MIMO_API_KEY) { $env:MIMO_API_KEY } else {
    [Environment]::GetEnvironmentVariable("MIMO_API_KEY", "User")
}
$UmansKey = if ($env:UMANS_API_KEY) { $env:UMANS_API_KEY } else {
    [Environment]::GetEnvironmentVariable("UMANS_API_KEY", "User")
}

$Providers = @{
    ds = @{
        name = "DeepSeek (direct)"
        url = "https://api.deepseek.com/anthropic"
        key = $DeepSeekKey; keyName = "DEEPSEEK_API_KEY"
        opus = "deepseek-v4-pro"; sonnet = "deepseek-v4-pro"
        haiku = "deepseek-v4-flash"; subagent = "deepseek-v4-flash"
    }
    or = @{
        name = "OpenRouter"
        url = "https://openrouter.ai/api"
        key = $OpenRouterKey; keyName = "OPENROUTER_API_KEY"
        opus = "deepseek/deepseek-v4-pro"; sonnet = "deepseek/deepseek-v4-pro"
        haiku = "deepseek/deepseek-v4-pro"; subagent = "deepseek/deepseek-v4-pro"
    }
    fw = @{
        name = "Fireworks AI"
        url = "https://api.fireworks.ai/inference"
        key = $FireworksKey; keyName = "FIREWORKS_API_KEY"
        opus = "accounts/fireworks/models/deepseek-v4-pro"
        sonnet = "accounts/fireworks/models/deepseek-v4-pro"
        haiku = "accounts/fireworks/models/deepseek-v4-pro"
        subagent = "accounts/fireworks/models/deepseek-v4-pro"
    }
    al = @{
        name = "DashScope (Alibaba Qwen)"
        url = "https://coding-intl.dashscope.aliyuncs.com/apps/anthropic"
        key = $DashScopeKey; keyName = "DASHSCOPE_API_KEY"
        opus = "qwen3.6-plus"; sonnet = "qwen3.6-plus"
        haiku = "qwen3.6-plus"; subagent = "qwen3.6-plus"
    }
    km = @{
        name = "Kimi K2.6 (Moonshot)"
        url = "https://api.moonshot.ai/anthropic"
        key = $KimiKey; keyName = "KIMI_API_KEY"
        opus = "kimi-k2.6"; sonnet = "kimi-k2.6"
        haiku = "kimi-k2.6"; subagent = "kimi-k2.6"
    }
    mm = @{
        name = "MiMo V2.5 (Xiaomi)"
        url = "https://token-plan-sgp.xiaomimimo.com/anthropic"
        key = $MimoKey; keyName = "MIMO_API_KEY"
        opus = "mimo-v2.5-pro"; sonnet = "mimo-v2.5"
        haiku = "mimo-v2.5"; subagent = "mimo-v2.5"
    }
    um = @{
        name = "Umans AI (gateway)"
        url = "https://api.code.umans.ai"
        key = $UmansKey; keyName = "UMANS_API_KEY"
        opus = "umans-kimi-k2.6"; sonnet = "umans-kimi-k2.6"
        haiku = "umans-kimi-k2.6"; subagent = "umans-kimi-k2.6"
    }
}

function Get-KeyDisplay($k) {
    if (-not $k) { return "MISSING" }
    return "set (****" + $k.Substring($k.Length - [Math]::Min(4, $k.Length)) + ")"
}

# --- Status ---
if ($Status) {
    Write-Host "`n  deepclaude - Backend Status" -ForegroundColor Cyan
    Write-Host "  ============================" -ForegroundColor DarkGray
    Write-Host "`n  Keys:" -ForegroundColor Yellow
    Write-Host "    DEEPSEEK_API_KEY:    $(Get-KeyDisplay $DeepSeekKey)"
    Write-Host "    OPENROUTER_API_KEY:  $(Get-KeyDisplay $OpenRouterKey)"
    Write-Host "    FIREWORKS_API_KEY:   $(Get-KeyDisplay $FireworksKey)"
    Write-Host "    DASHSCOPE_API_KEY:   $(Get-KeyDisplay $DashScopeKey)"
    Write-Host "    KIMI_API_KEY:        $(Get-KeyDisplay $KimiKey)"
    Write-Host "    MIMO_API_KEY:        $(Get-KeyDisplay $MimoKey)"
    Write-Host "    UMANS_API_KEY:       $(Get-KeyDisplay $UmansKey)"
    Write-Host "`n  Backends:" -ForegroundColor Yellow
    Write-Host "    deepclaude              # DeepSeek V4 Pro (default)"
    Write-Host "    deepclaude -b or        # OpenRouter (cheapest)"
    Write-Host "    deepclaude -b fw        # Fireworks AI (fastest)"
    Write-Host "    deepclaude -b al        # DashScope (Alibaba Qwen)"
    Write-Host "    deepclaude -b km        # Kimi K2.6 (Moonshot)"
    Write-Host "    deepclaude -b mm        # MiMo V2.5 (Xiaomi)"
    Write-Host "    deepclaude -b um        # Umans AI (gateway)"
    Write-Host "    deepclaude -b anthropic # Normal Claude Code"
    Write-Host ""
    exit 0
}

# --- List proxies ---
if ($List) {
    Write-Host "`n  Active deepclaude Proxies" -ForegroundColor Cyan
    Write-Host "  ==========================" -ForegroundColor DarkGray
    Write-Host ""

    $tmpDir = if ($env:TMPDIR) { $env:TMPDIR } else { $env:TEMP }
    $found = $false

    Get-ChildItem "$tmpDir\deepclaude-proxy-*.json" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $state = Get-Content $_.FullName -Raw | ConvertFrom-Json
            $pid = $state.pid
            $port = $state.port
            $mode = if ($state.mode) { $state.mode } else { "?" }

            $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
            if (-not $proc) {
                Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                return
            }

            $found = $true
            $health = Invoke-RestMethod -Uri "http://127.0.0.1:$port/_proxy/status" -ErrorAction SilentlyContinue
            if ($health) {
                Write-Host "  :$port  pid=$pid  mode=$mode  requests=$($health.requests)"
            } else {
                Write-Host "  :$port  pid=$pid  mode=$mode  (unreachable)" -ForegroundColor Yellow
            }
        } catch {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not $found) {
        Write-Host "  No active proxies found." -ForegroundColor DarkGray
    }
    Write-Host ""
    exit 0
}

# --- Cost ---
if ($Cost) {
    Write-Host "`n  DeepSeek V4 Pro Pricing" -ForegroundColor Cyan
    Write-Host "  =======================" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Provider        Input/M    Output/M   Cache Hit/M" -ForegroundColor Yellow
    Write-Host "  ----------      --------   --------   -----------"
    Write-Host "  DeepSeek        `$0.44      `$0.87      `$0.004" -ForegroundColor Green
    Write-Host "  OpenRouter      `$0.44      `$0.87      (provider)"
    Write-Host "  Fireworks       `$1.74      `$3.48      (provider)"
    Write-Host "  Anthropic       `$3.00      `$15.00     `$0.30"
    Write-Host ""
    Write-Host "  Monthly estimate (heavy use): `$30-80 vs `$200 Anthropic" -ForegroundColor Green
    Write-Host ""
    exit 0
}

# --- Help ---
if ($Help) {
    Write-Host "deepclaude - Claude Code with cheap backends"
    Write-Host ""
    Write-Host "Usage: deepclaude [-b backend] [--status] [--list] [--cost] [--benchmark]"
    Write-Host "       deepclaude --switch <backend> [--port <n>]"
    Write-Host ""
    Write-Host "  -b, --backend   ds (default), or, fw, al, km, mm, um, anthropic"
    Write-Host "  --status        Show keys and backends"
    Write-Host "  --list, -l        List active proxies"
    Write-Host "  --cost          Pricing comparison"
    Write-Host "  --benchmark     Latency test"
    Write-Host "  --switch, -s    Switch proxy backend"
    Write-Host "  --port          Target specific proxy port for --switch"
    exit 0
}

# --- Benchmark ---
if ($Benchmark) {
    Write-Host "`n  Latency Benchmark" -ForegroundColor Cyan
    Write-Host "  ==================" -ForegroundColor DarkGray
    foreach ($id in @("ds","or","fw","al","km","mm")) {
        $p = $Providers[$id]
        Write-Host "  $($p.name)..." -NoNewline
        if (-not $p.key) { Write-Host " SKIP (no key)" -ForegroundColor DarkGray; continue }
        $useBearer = $id -in @("or","fw","al","km","mm")
        $headers = if ($useBearer) {
            @{ "Authorization" = "Bearer $($p.key)"; "content-type" = "application/json"; "anthropic-version" = "2023-06-01" }
        } else {
            @{ "x-api-key" = $p.key; "content-type" = "application/json"; "anthropic-version" = "2023-06-01" }
        }
        $body = @{ model = $p.opus; max_tokens = 32; messages = @(@{ role = "user"; content = "Reply: ok" }) } | ConvertTo-Json -Depth 5
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $null = Invoke-RestMethod -Uri "$($p.url)/v1/messages" -Method POST -Headers $headers -Body $body -TimeoutSec 30
            $sw.Stop()
            Write-Host " OK ($($sw.ElapsedMilliseconds)ms)" -ForegroundColor Green
        } catch {
            $sw.Stop()
            $code = if ($_.Exception.Response) { $_.Exception.Response.StatusCode.value__ } else { "timeout" }
            Write-Host " FAIL ($code, $($sw.ElapsedMilliseconds)ms)" -ForegroundColor Red
        }
    }
    Write-Host ""
    exit 0
}

# --- Remote ---
if ($Remote) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    if ($Backend -eq "anthropic") {
        Write-Host "`n  Launching remote control (Anthropic)...`n" -ForegroundColor Cyan
        foreach ($v in @("ANTHROPIC_BASE_URL","ANTHROPIC_AUTH_TOKEN","ANTHROPIC_DEFAULT_OPUS_MODEL",
            "ANTHROPIC_DEFAULT_SONNET_MODEL","ANTHROPIC_DEFAULT_HAIKU_MODEL",
            "CLAUDE_CODE_SUBAGENT_MODEL","CLAUDE_CODE_EFFORT_LEVEL")) {
            Remove-Item "Env:$v" -ErrorAction SilentlyContinue
        }
        Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
        & claude remote-control @Args
        exit 0
    }

    $p = $Providers[$Backend]
    if (-not $p) { Write-Host "ERROR: Unknown backend '$Backend'" -ForegroundColor Red; exit 1 }
    if (-not $p.key) { Write-Host "ERROR: $($p.keyName) not set" -ForegroundColor Red; exit 1 }

    Write-Host "`n  Starting model proxy for $($p.name)..." -ForegroundColor Cyan

    $proxyScript = Join-Path $ScriptDir "proxy\start-proxy.js"
    $proxyProc = Start-Process -FilePath "node" -ArgumentList $proxyScript,$p.url,$p.key -PassThru -WindowStyle Hidden -RedirectStandardOutput "$env:TEMP\deepclaude-proxy-port.txt"

    $tries = 0
    while ($tries -lt 30) {
        Start-Sleep -Milliseconds 200
        $tries++
        if (Test-Path "$env:TEMP\deepclaude-proxy-port.txt") {
            $content = Get-Content "$env:TEMP\deepclaude-proxy-port.txt" -ErrorAction SilentlyContinue
            if ($content) { break }
        }
    }

    $proxyPort = (Get-Content "$env:TEMP\deepclaude-proxy-port.txt" -ErrorAction SilentlyContinue | Select-Object -First 1)
    Remove-Item "$env:TEMP\deepclaude-proxy-port.txt" -ErrorAction SilentlyContinue

    if (-not $proxyPort) {
        Write-Host "ERROR: Proxy failed to start" -ForegroundColor Red
        if ($proxyProc -and -not $proxyProc.HasExited) { Stop-Process -Id $proxyProc.Id -Force }
        exit 1
    }

    Write-Host "  Proxy on :$proxyPort -> $($p.url)" -ForegroundColor DarkGray
    Write-Host "  Launching remote control via $($p.name)...`n" -ForegroundColor Cyan

    $env:ANTHROPIC_BASE_URL = "http://127.0.0.1:$proxyPort"
    $env:ANTHROPIC_DEFAULT_OPUS_MODEL = $p.opus
    $env:ANTHROPIC_DEFAULT_SONNET_MODEL = $p.sonnet
    $env:ANTHROPIC_DEFAULT_HAIKU_MODEL = $p.haiku
    $env:CLAUDE_CODE_SUBAGENT_MODEL = $p.subagent
    $env:CLAUDE_CODE_EFFORT_LEVEL = "max"
    Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:ANTHROPIC_AUTH_TOKEN -ErrorAction SilentlyContinue

    try {
        & claude remote-control @Args
    } finally {
        if ($proxyProc -and -not $proxyProc.HasExited) {
            Stop-Process -Id $proxyProc.Id -Force -ErrorAction SilentlyContinue
            Write-Host "  Proxy stopped." -ForegroundColor DarkGray
        }
    }
    exit 0
}

# --- Launch ---
if ($Backend -eq "anthropic") {
    foreach ($v in @("ANTHROPIC_BASE_URL","ANTHROPIC_AUTH_TOKEN","ANTHROPIC_DEFAULT_OPUS_MODEL",
        "ANTHROPIC_DEFAULT_SONNET_MODEL","ANTHROPIC_DEFAULT_HAIKU_MODEL",
        "CLAUDE_CODE_SUBAGENT_MODEL","CLAUDE_CODE_EFFORT_LEVEL")) {
        Remove-Item "Env:$v" -ErrorAction SilentlyContinue
    }
    Write-Host "`n  Launching Claude Code (normal Anthropic)...`n" -ForegroundColor Cyan
    & claude @Args
    exit 0
}

$p = $Providers[$Backend]
if (-not $p) { Write-Host "ERROR: Unknown backend '$Backend'. Use: ds, or, fw, al, anthropic" -ForegroundColor Red; exit 1 }
if (-not $p.key) { Write-Host "ERROR: $($p.keyName) not set" -ForegroundColor Red; exit 1 }

Write-Host "`n  Launching Claude Code via $($p.name)..." -ForegroundColor Cyan
Write-Host "  Endpoint: $($p.url)" -ForegroundColor DarkGray
Write-Host "  Model: $($p.opus) (main) + $($p.haiku) (subagents)" -ForegroundColor DarkGray
Write-Host ""

$env:ANTHROPIC_BASE_URL = $p.url
$env:ANTHROPIC_AUTH_TOKEN = $p.key
$env:ANTHROPIC_MODEL = $p.opus
$env:ANTHROPIC_DEFAULT_OPUS_MODEL = $p.opus
$env:ANTHROPIC_DEFAULT_SONNET_MODEL = $p.sonnet
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL = $p.haiku
$env:CLAUDE_CODE_SUBAGENT_MODEL = $p.subagent
$env:CLAUDE_CODE_EFFORT_LEVEL = "max"
Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue

& claude @Args

foreach ($v in @("ANTHROPIC_BASE_URL","ANTHROPIC_AUTH_TOKEN","ANTHROPIC_MODEL",
    "ANTHROPIC_DEFAULT_OPUS_MODEL","ANTHROPIC_DEFAULT_SONNET_MODEL",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL","CLAUDE_CODE_SUBAGENT_MODEL","CLAUDE_CODE_EFFORT_LEVEL")) {
    Remove-Item "Env:$v" -ErrorAction SilentlyContinue
}
