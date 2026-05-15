#!/usr/bin/env bash
# deepclaude — Use Claude Code with DeepSeek V4 Pro or other cheap backends
# Usage: deepclaude [--backend ds|or|fw|anthropic] [--remote] [--status] [--cost] [--benchmark]

set -euo pipefail

# Load .env file if present
if [[ -f ".env" ]]; then
    set -a
    source ".env"
    set +a
fi

# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

## by chatgpt
SOURCE="${BASH_SOURCE[0]}"

while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done

SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
## end chapgpt

# --- Config ---
DEEPSEEK_URL="https://api.deepseek.com/anthropic"
OPENROUTER_URL="https://openrouter.ai/api"
FIREWORKS_URL="https://api.fireworks.ai/inference"
DASHSCOPE_URL="https://coding-intl.dashscope.aliyuncs.com/apps/anthropic"
KIMI_URL="https://api.moonshot.ai/anthropic"
MIMO_URL="https://token-plan-sgp.xiaomimimo.com/anthropic"
UMANS_URL="https://api.code.umans.ai"

BACKEND="${CHEAPCLAUDE_DEFAULT_BACKEND:-ds}"
ACTION="launch"
SWITCH_BACKEND=""
PROXY_PID=""
SWITCH_PORT=""

# --- Parse args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --backend|-b) BACKEND="$2"; shift 2 ;;
        --switch|-s)  ACTION="switch"; SWITCH_BACKEND="$2"; shift 2 ;;
        --remote|-r)  ACTION="remote"; shift ;;
        --status)     ACTION="status"; shift ;;
        --cost)       ACTION="cost"; shift ;;
        --benchmark)  ACTION="benchmark"; shift ;;
        --list|-l)    ACTION="list"; shift ;;
        --port|-p)  SWITCH_PORT="$2"; shift 2 ;;
        --help|-h)    ACTION="help"; shift ;;
        *)            break ;;
    esac
done

cleanup_proxy() {
    if [[ -n "$PROXY_PID" ]] && kill -0 "$PROXY_PID" 2>/dev/null; then
        kill "$PROXY_PID" 2>/dev/null || true
        echo "  Proxy stopped."
    fi
}
trap cleanup_proxy EXIT

mask_key() {
    local k="$1"
    if [[ -z "$k" ]]; then echo "MISSING"; else echo "set (****${k: -4})"; fi
}

resolve_backend() {
    local url="" key="" opus="" sonnet="" haiku="" subagent=""
    case "$BACKEND" in
        ds|deepseek)
            key="${DEEPSEEK_API_KEY:-}"
            [[ -z "$key" ]] && { echo "ERROR: DEEPSEEK_API_KEY not set" >&2; exit 1; }
            url="$DEEPSEEK_URL"
            opus="deepseek-v4-pro"; sonnet="deepseek-v4-pro"
            haiku="deepseek-v4-flash"; subagent="deepseek-v4-flash"
            ;;
        or|openrouter)
            key="${OPENROUTER_API_KEY:-}"
            [[ -z "$key" ]] && { echo "ERROR: OPENROUTER_API_KEY not set" >&2; exit 1; }
            url="$OPENROUTER_URL"
            opus="deepseek/deepseek-v4-pro"; sonnet="deepseek/deepseek-v4-pro"
            haiku="deepseek/deepseek-v4-pro"; subagent="deepseek/deepseek-v4-pro"
            ;;
        fw|fireworks)
            key="${FIREWORKS_API_KEY:-}"
            [[ -z "$key" ]] && { echo "ERROR: FIREWORKS_API_KEY not set" >&2; exit 1; }
            url="$FIREWORKS_URL"
            opus="accounts/fireworks/models/deepseek-v4-pro"
            sonnet="accounts/fireworks/models/deepseek-v4-pro"
            haiku="accounts/fireworks/models/deepseek-v4-pro"
            subagent="accounts/fireworks/models/deepseek-v4-pro"
            ;;
        al|dashscope|aliyun)
            key="${DASHSCOPE_API_KEY:-}"
            [[ -z "$key" ]] && { echo "ERROR: DASHSCOPE_API_KEY not set" >&2; exit 1; }
            url="$DASHSCOPE_URL"
            opus="qwen3.6-plus"; sonnet="qwen3.6-plus"
            haiku="qwen3.6-plus"; subagent="qwen3.6-plus"
            ;;
        km|kimi|moonshot)
            key="${KIMI_API_KEY:-}"
            [[ -z "$key" ]] && { echo "ERROR: KIMI_API_KEY not set" >&2; exit 1; }
            url="$KIMI_URL"
            opus="kimi-k2.6"; sonnet="kimi-k2.6"
            haiku="kimi-k2.6"; subagent="kimi-k2.6"
            ;;
        mm|mimo|xiaomi)
            key="${MIMO_API_KEY:-}"
            [[ -z "$key" ]] && { echo "ERROR: MIMO_API_KEY not set" >&2; exit 1; }
            url="$MIMO_URL"
            opus="mimo-v2.5-pro"; sonnet="mimo-v2.5"
            haiku="mimo-v2.5"; subagent="mimo-v2.5"
            ;;
        um|umans)
            key="${UMANS_API_KEY:-}"
            [[ -z "$key" ]] && { echo "ERROR: UMANS_API_KEY not set" >&2; exit 1; }
            url="$UMANS_URL"
            opus="umans-kimi-k2.6"; sonnet="umans-kimi-k2.6"
            haiku="umans-kimi-k2.6"; subagent="umans-kimi-k2.6"
            ;;
        anthropic) ;;
        *) echo "ERROR: Unknown backend '$BACKEND'. Use: ds, or, fw, al, km, mm, um, anthropic" >&2; exit 1 ;;
    esac
    RESOLVED_URL="$url"; RESOLVED_KEY="$key"
    RESOLVED_OPUS="$opus"; RESOLVED_SONNET="$sonnet"
    RESOLVED_HAIKU="$haiku"; RESOLVED_SUBAGENT="$subagent"
}

set_model_env() {
    export ANTHROPIC_DEFAULT_OPUS_MODEL="$RESOLVED_OPUS"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="$RESOLVED_SONNET"
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="$RESOLVED_HAIKU"
    export CLAUDE_CODE_SUBAGENT_MODEL="$RESOLVED_SUBAGENT"
    export CLAUDE_CODE_EFFORT_LEVEL="max"
}

show_status() {
    echo ""
    echo "  deepclaude — Backend Status"
    echo "  ============================"
    echo ""
    echo "  Keys:"
    echo "    DEEPSEEK_API_KEY:    $(mask_key "${DEEPSEEK_API_KEY:-}")"
    echo "    OPENROUTER_API_KEY:  $(mask_key "${OPENROUTER_API_KEY:-}")"
    echo "    FIREWORKS_API_KEY:   $(mask_key "${FIREWORKS_API_KEY:-}")"
    echo "    DASHSCOPE_API_KEY:   $(mask_key "${DASHSCOPE_API_KEY:-}")"
    echo "    KIMI_API_KEY:        $(mask_key "${KIMI_API_KEY:-}")"
    echo "    MIMO_API_KEY:        $(mask_key "${MIMO_API_KEY:-}")"
    echo "    UMANS_API_KEY:       $(mask_key "${UMANS_API_KEY:-}")"
    echo ""
    echo "  Backends:"
    echo "    deepclaude                  # DeepSeek V4 Pro (default)"
    echo "    deepclaude -b or            # OpenRouter (cheapest)"
    echo "    deepclaude -b fw            # Fireworks AI (fastest)"
    echo "    deepclaude -b al            # DashScope (Alibaba Qwen)"
    echo "    deepclaude -b km            # Kimi K2.6 (Moonshot)"
    echo "    deepclaude -b mm            # MiMo V2.5 (Xiaomi)"
    echo "    deepclaude -b um            # Umans AI (gateway)"
    echo "    deepclaude -b anthropic     # Normal Claude Code"
    echo "    deepclaude --remote         # Remote control + DeepSeek"
    echo "    deepclaude --remote -b or   # Remote control + OpenRouter"
    echo ""
    local proxy_status
    proxy_status=$(curl -s http://127.0.0.1:3200/_proxy/status 2>/dev/null) || proxy_status=""
    if [[ -n "$proxy_status" ]]; then
        echo "  Proxy: running"
        echo "    $proxy_status"
    else
        echo "  Proxy: not running"
    fi
    echo ""
}

show_list() {
    echo ""
    echo "  Active deepclaude Proxies"
    echo "  =========================="
    echo ""

    local tmp_dir="${TMPDIR:-/tmp}"
    local found=0
    for state_file in "$tmp_dir"/deepclaude-proxy-*.json; do
        [[ -f "$state_file" ]] || continue

        local pid port mode started
        pid=$(jq -r '.pid // empty' "$state_file" 2>/dev/null) || continue
        port=$(jq -r '.port // empty' "$state_file" 2>/dev/null) || continue
        mode=$(jq -r '.mode // "?"' "$state_file" 2>/dev/null)
        started=$(jq -r '.started // "?"' "$state_file" 2>/dev/null)

        # Check if process is still alive
        if ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$state_file"
            continue
        fi

        found=1
        local status="alive"
        local health
        health=$(curl -s "http://127.0.0.1:$port/_proxy/status" 2>/dev/null) || health=""
        if [[ -n "$health" ]]; then
            local req_count
            req_count=$(echo "$health" | jq -r '.requests // "?"' 2>/dev/null)
            echo "  :$port  pid=$pid  mode=$mode  requests=$req_count"
        else
            echo "  :$port  pid=$pid  mode=$mode  (unreachable)"
        fi
    done

    if [[ $found -eq 0 ]]; then
        echo "  No active proxies found."
    fi
    echo ""
}

show_cost() {
    echo ""
    echo "  DeepSeek V4 Pro Pricing"
    echo "  ======================="
    echo ""
    echo "  Provider        Input/M    Output/M   Cache Hit/M"
    echo "  ----------      --------   --------   -----------"
    echo "  DeepSeek        \$0.44      \$0.87      \$0.004"
    echo "  OpenRouter      \$0.44      \$0.87      (provider)"
    echo "  Fireworks       \$1.74      \$3.48      (provider)"
    echo "  Anthropic       \$3.00      \$15.00     \$0.30"
    echo ""
    echo "  Monthly estimate (heavy use, 25 days): \$30-80"
    echo ""
}

show_help() {
    echo "deepclaude — Claude Code with cheap backends"
    echo ""
    echo "Usage: deepclaude [options] [-- claude-args...]"
    echo ""
    echo "Options:"
    echo "  -b, --backend <ds|or|fw|al|km|mm|um|anthropic>  Backend (default: ds)"
    echo "  -r, --remote                        Remote control mode (browser URL)"
    echo "  --status                             Show keys and backends"
    echo "  --cost                               Pricing comparison"
    echo "  --benchmark                          Latency test"
    echo "  -s, --switch <backend>               Switch proxy mid-session"
    echo "  -p, --port <n>                       Proxy port for --switch"
    echo "  --list, -l                         List active proxies"
    echo "  -h, --help                           This help"
    echo ""
    echo "Environment variables:"
    echo "  DEEPSEEK_API_KEY      DeepSeek API key (required for ds)"
    echo "  OPENROUTER_API_KEY    OpenRouter API key (required for or)"
    echo "  FIREWORKS_API_KEY     Fireworks API key (required for fw)"
    echo "  DASHSCOPE_API_KEY     DashScope API key (required for al)"
    echo "  KIMI_API_KEY          Kimi API key (required for km)"
    echo "  MIMO_API_KEY          MiMo API key (required for mm)"
    echo "  UMANS_API_KEY         Umans API key (required for um)"
    echo "  CHEAPCLAUDE_DEFAULT_BACKEND  Default backend (default: ds)"
}

do_switch() {
    local backend="$SWITCH_BACKEND"
    case "$backend" in
        ds|deepseek)   backend="deepseek" ;;
        or|openrouter) backend="openrouter" ;;
        fw|fireworks)  backend="fireworks" ;;
        al|dashscope|aliyun) backend="dashscope" ;;
        km|kimi|moonshot)    backend="kimi" ;;
        mm|mimo|xiaomi)      backend="mimo" ;;
        um|umans)            backend="umans" ;;
        anthropic)     backend="anthropic" ;;
        *) echo "ERROR: Unknown backend '$backend'. Use: ds, or, fw, al, km, mm, um, anthropic" >&2; exit 1 ;;
    esac

    # Resolve proxy target: --port > ANTHROPIC_BASE_URL > fallback 3200
    local proxy_url
    if [[ -n "$SWITCH_PORT" ]]; then
        proxy_url="http://127.0.0.1:$SWITCH_PORT"
    elif [[ -n "${ANTHROPIC_BASE_URL:-}" ]]; then
        proxy_url="$ANTHROPIC_BASE_URL"
    else
        proxy_url="http://127.0.0.1:3200"
    fi

    local resp
    resp=$(curl -sX POST "$proxy_url/_proxy/mode" -d "backend=$backend" 2>/dev/null) || {
        echo "  Proxy not running at $proxy_url" >&2; exit 1
    }
    echo "  $resp"
}

run_benchmark() {
    echo ""
    echo "  Latency Benchmark (1 request each)"
    echo "  ==================================="
    for name in deepseek openrouter fireworks; do
        local url="" key="" model=""
        case "$name" in
            deepseek)   url="$DEEPSEEK_URL"; key="${DEEPSEEK_API_KEY:-}"; model="deepseek-v4-pro" ;;
            openrouter) url="$OPENROUTER_URL"; key="${OPENROUTER_API_KEY:-}"; model="deepseek/deepseek-v4-pro" ;;
            fireworks)  url="$FIREWORKS_URL"; key="${FIREWORKS_API_KEY:-}"; model="accounts/fireworks/models/deepseek-v4-pro" ;;
        esac
        if [[ -z "$key" ]]; then echo "  $name: SKIP (no key)"; continue; fi
        local start_ms=$(date +%s%3N 2>/dev/null || python3 -c 'import time;print(int(time.time()*1000))')
        local status=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$url/v1/messages" \
            -H "x-api-key: $key" -H "content-type: application/json" -H "anthropic-version: 2023-06-01" \
            -d "{\"model\":\"$model\",\"max_tokens\":32,\"messages\":[{\"role\":\"user\",\"content\":\"Reply: ok\"}]}" \
            --max-time 30 2>/dev/null || echo "timeout")
        local end_ms=$(date +%s%3N 2>/dev/null || python3 -c 'import time;print(int(time.time()*1000))')
        local elapsed=$((end_ms - start_ms))
        if [[ "$status" == "200" ]]; then
            echo "  $name: OK (${elapsed}ms)"
        else
            echo "  $name: FAIL ($status, ${elapsed}ms)"
        fi
    done
    echo ""
}

launch_claude() {
    if [[ "$BACKEND" == "anthropic" ]]; then
        echo "  Launching Claude Code (normal Anthropic backend)..."
        unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN
        unset ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL
        unset ANTHROPIC_DEFAULT_HAIKU_MODEL CLAUDE_CODE_SUBAGENT_MODEL
        unset CLAUDE_CODE_EFFORT_LEVEL
        exec claude "$@"
    fi

    resolve_backend

    local proxy_mode
    case "$BACKEND" in
        ds|deepseek)   proxy_mode="deepseek" ;;
        or|openrouter) proxy_mode="openrouter" ;;
        fw|fireworks)  proxy_mode="fireworks" ;;
        al|dashscope|aliyun) proxy_mode="dashscope" ;;
        km|kimi|moonshot)    proxy_mode="kimi" ;;
        mm|mimo|xiaomi)      proxy_mode="mimo" ;;
        um|umans)            proxy_mode="umans" ;;
        *)             proxy_mode="deepseek" ;;
    esac

    echo "  Starting model proxy for $BACKEND (mode: $proxy_mode)..."

    local port_file
    port_file=$(mktemp)
    node "$SCRIPT_DIR/proxy/start-proxy.js" "$RESOLVED_URL" "$RESOLVED_KEY" "$proxy_mode" > "$port_file" &
    PROXY_PID=$!

    local tries=0
    while [[ ! -s "$port_file" ]] && [[ $tries -lt 30 ]]; do
        sleep 0.2
        tries=$((tries + 1))
    done

    if [[ ! -s "$port_file" ]]; then
        echo "ERROR: Proxy failed to start" >&2
        rm -f "$port_file"
        exit 1
    fi

    local proxy_port
    proxy_port=$(head -1 "$port_file")
    rm -f "$port_file"

    echo "  Proxy on :$proxy_port -> $RESOLVED_URL"
    echo "  Launching Claude Code via proxy..."
    echo ""

    export ANTHROPIC_BASE_URL="http://127.0.0.1:$proxy_port"
    export ANTHROPIC_AUTH_TOKEN="proxy"
    set_model_env
    unset ANTHROPIC_API_KEY

    claude "$@"
}

launch_remote() {
    if [[ "$BACKEND" == "anthropic" ]]; then
        echo "  Launching remote control (Anthropic)..."
        unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN
        unset ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL
        unset ANTHROPIC_DEFAULT_HAIKU_MODEL CLAUDE_CODE_SUBAGENT_MODEL
        unset CLAUDE_CODE_EFFORT_LEVEL ANTHROPIC_API_KEY
        claude remote-control "$@"
    fi

    resolve_backend

    local proxy_mode
    case "$BACKEND" in
        ds|deepseek)   proxy_mode="deepseek" ;;
        or|openrouter) proxy_mode="openrouter" ;;
        fw|fireworks)  proxy_mode="fireworks" ;;
        al|dashscope|aliyun) proxy_mode="dashscope" ;;
        km|kimi|moonshot)    proxy_mode="kimi" ;;
        mm|mimo|xiaomi)      proxy_mode="mimo" ;;
        um|umans)            proxy_mode="umans" ;;
        *)             proxy_mode="deepseek" ;;
    esac

    echo "  Starting model proxy for $BACKEND (mode: $proxy_mode)..."

    local port_file
    port_file=$(mktemp)
    node "$SCRIPT_DIR/proxy/start-proxy.js" "$RESOLVED_URL" "$RESOLVED_KEY" "$proxy_mode" > "$port_file" &
    PROXY_PID=$!

    local tries=0
    while [[ ! -s "$port_file" ]] && [[ $tries -lt 30 ]]; do
        sleep 0.2
        tries=$((tries + 1))
    done

    if [[ ! -s "$port_file" ]]; then
        echo "ERROR: Proxy failed to start" >&2
        rm -f "$port_file"
        exit 1
    fi

    local proxy_port
    proxy_port=$(head -1 "$port_file")
    rm -f "$port_file"

    echo "  Proxy on :$proxy_port -> $RESOLVED_URL"
    echo "  Launching remote control via $BACKEND..."
    echo ""

    export ANTHROPIC_BASE_URL="http://127.0.0.1:$proxy_port"
    set_model_env
    unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN

    claude remote-control "$@"
}

# --- Main ---
case "$ACTION" in
    status)    show_status ;;
    list)      show_list ;;
    cost)      show_cost ;;
    benchmark) run_benchmark ;;
    help)      show_help ;;
    switch)    do_switch ;;
    remote)    launch_remote "$@" ;;
    launch)    launch_claude "$@" ;;
esac
