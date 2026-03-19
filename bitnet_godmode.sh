#!/bin/bash
# =================================================================
# 🛡️ BITNET OMNI-SHIELD: LIVE MONITOR + PLUGIN MARKET + METADATA
# =================================================================
set -e

NC='\033[0m'; RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
LOG_DIR="./chat_logs"
LOG_FILE="$LOG_DIR/system.log"
M_PATH="./models/default.gguf"
PLUGIN_DIR="./plugins"
MARKET_DIR="./marketplace"
BENCH_FILE="./.bitnet_benchmark"
LLAMA_BIN="./build/bin/llama-bench"

mkdir -p "$LOG_DIR" "$PLUGIN_DIR" "$MARKET_DIR"

# ================================================================
# 🔧 DEPENDENCY ENGINE
# ================================================================
require_tool() {
    NAME="$1"; CHECK_CMD="$2"; FIX_FUNC="$3"
    if eval "$CHECK_CMD" &>/dev/null; then
        echo -e "${GREEN}✅ $NAME OK${NC}"; return 0
    fi
    echo -e "${YELLOW}⚠️ Missing: $NAME — fixing...${NC}"
    declare -f "$FIX_FUNC" >/dev/null && $FIX_FUNC || { echo -e "${RED}❌ No fix for $NAME${NC}"; return 1; }
    eval "$CHECK_CMD" &>/dev/null && echo -e "${GREEN}✅ $NAME fixed${NC}" || return 1
}

fix_llama_bench() { rm -rf build; mkdir build && cd build; cmake .. && make -j$(nproc); cd ..; }
fix_python() { sudo apt update && sudo apt install -y python3 python3-pip python3-venv; }
fix_cmake() { sudo apt update && sudo apt install -y cmake; }
fix_ffmpeg() { sudo apt install -y ffmpeg; }

# ================================================================
# 🧩 PLUGIN SYSTEM (METADATA + DEPS)
# ================================================================
parse_metadata() {
    FILE="$1"
    NAME=$(grep "#@name:" "$FILE" | cut -d: -f2- | xargs)
    DESC=$(grep "#@desc:" "$FILE" | cut -d: -f2- | xargs)
    DEPS=$(grep "#@deps:" "$FILE" | cut -d: -f2- | xargs)
}

handle_deps() {
    for dep in $DEPS; do
        case $dep in
            python) require_tool "python3" "command -v python3" fix_python ;;
            cmake) require_tool "cmake" "command -v cmake" fix_cmake ;;
            ffmpeg) require_tool "ffmpeg" "command -v ffmpeg" fix_ffmpeg ;;
            llama) require_tool "llama-bench" "[[ -f $LLAMA_BIN ]]" fix_llama_bench ;;
        esac
    done
}

run_plugin() {
    FILE="$1"; parse_metadata "$FILE"
    echo -e "${CYAN}▶ Running: ${NAME:-$(basename "$FILE")}${NC}"
    [[ -n "$DESC" ]] && echo -e "${YELLOW}$DESC${NC}"
    handle_deps
    source "$FILE"
}

list_plugins() { ls "$PLUGIN_DIR"/*.sh 2>/dev/null | sort; }

# ================================================================
# 🛒 PLUGIN MARKETPLACE (LOCAL)
# ================================================================
market_list() {
    echo -e "${CYAN}📦 Available plugins:${NC}"
    ls "$MARKET_DIR"/*.sh 2>/dev/null | xargs -n1 basename
}

market_install() {
    NAME="$1"
    SRC="$MARKET_DIR/$NAME.sh"
    DST="$PLUGIN_DIR/$NAME.sh"
    if [[ -f "$SRC" ]]; then
        cp "$SRC" "$DST"
        echo -e "${GREEN}✅ Installed $NAME${NC}"
    else
        echo -e "${RED}❌ Plugin not found in marketplace${NC}"
    fi
}

market_remove() {
    NAME="$1"
    FILE="$PLUGIN_DIR/$NAME.sh"
    [[ -f "$FILE" ]] && rm "$FILE" && echo -e "${GREEN}🗑️ Removed $NAME${NC}"
}

# ================================================================
# ⚡ BENCHMARK
# ================================================================
run_benchmark() {
    require_tool "llama-bench" "[[ -f $LLAMA_BIN ]]" fix_llama_bench || return
    BEST="CPU"; SCORE=0
    test_backend() {
        NAME=$1; CMD=$2
        OUT=$(eval "$CMD" 2>/dev/null || true)
        TOK=$(echo "$OUT" | grep -i tok/s | awk '{print $(NF-1)}' | head -n1)
        TOK=${TOK:-0}
        if (( $(echo "$TOK > $SCORE" | bc -l) )); then SCORE=$TOK; BEST=$NAME; fi
    }
    test_backend "CPU" "$LLAMA_BIN -m $M_PATH -t $(nproc) -n 64"
    command -v nvidia-smi &>/dev/null && test_backend "CUDA" "$LLAMA_BIN -m $M_PATH -ngl 999 -n 64"
    echo "backend=$BEST" > "$BENCH_FILE"
    echo "tokens_per_sec=$SCORE" >> "$BENCH_FILE"
}

load_benchmark() { [[ -f "$BENCH_FILE" ]] && source "$BENCH_FILE"; }

# ================================================================
# 📊 LIVE MONITOR
# ================================================================
get_cpu() { top -bn1 | grep "Cpu(s)" | awk '{print $2+$4 "%"}'; }
get_ram() { free -h | awk '/Mem:/ {print $3 "/" $2}'; }
get_gpu() { command -v nvidia-smi &>/dev/null && nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | head -n1 | awk '{print $1 "%"}' || echo "N/A"; }

print_header() {
    load_benchmark
    CPU=$(get_cpu); RAM=$(get_ram); GPU=$(get_gpu)
    echo -e "${GREEN}CPU: $CPU | RAM: $RAM | GPU: $GPU | Backend: ${backend:-?} | Speed: ${tokens_per_sec:-?}${NC}"
}

# ================================================================
# 🧪 DEFAULT PLUGINS
# ================================================================
create_default_plugins() {
cat << 'EOF' > "$PLUGIN_DIR/chat.sh"
#@name: Chat
#@desc: Terminal chat
#@deps: python

echo "💬 Chat running"
EOF
}
[[ -z "$(ls -A $PLUGIN_DIR 2>/dev/null)" ]] && create_default_plugins

# ================================================================
# 🧭 MAIN LOOP
# ================================================================
while true; do
    print_header
    echo -e "\n${CYAN}=========== OMNI-SHIELD ===========${NC}"

    i=1; declare -A MAP

    for plugin in $(list_plugins); do
        parse_metadata "$plugin"
        echo "$i) ⚙️  ${NAME:-$(basename "$plugin" .sh)}"
        MAP[$i]="$plugin"; ((i++))
    done

    echo "$i) 📦 market list"; MAP[$i]="market_list"; ((i++))
    echo "$i) 📥 install plugin"; MAP[$i]="install"; ((i++))
    echo "$i) 🗑️ remove plugin"; MAP[$i]="remove"; ((i++))
    echo "$i) ⚡ benchmark"; MAP[$i]="benchmark"; ((i++))
    echo "$i) 🚪 exit"; MAP[$i]="exit"

    read -p "Select: " CHOICE
    ACTION=${MAP[$CHOICE]}

    case $ACTION in
        *.sh) run_plugin "$ACTION" ;;
        market_list) market_list ;;
        install) read -p "Plugin name: " P; market_install "$P" ;;
        remove) read -p "Plugin name: " P; market_remove "$P" ;;
        benchmark) run_benchmark ;;
        exit) exit 0 ;;
        *) echo "Invalid" ;;
    esac

done

# ================================================================
# 📘 README (auto-generated reference)
# ================================================================
: <<'README'
# BitNet Omni-Shield

## Features
- Plugin system with metadata (#@name, #@desc, #@deps)
- Self-healing dependency manager
- Real llama.cpp benchmarking
- Live CPU/RAM/GPU monitor
- Local plugin marketplace

## Plugin Format
#@name: Name
#@desc: Description
#@deps: python ffmpeg llama

## Commands
- Add plugin: place .sh in ./plugins/
- Marketplace: ./marketplace/
- Benchmark: menu option

## Requirements
- cmake, python3, llama.cpp build

README
