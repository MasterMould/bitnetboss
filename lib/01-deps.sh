#!/bin/bash
# ================================================================
# 01-deps.sh — Self-healing dependency engine
# Requires: 00-globals.sh
# ================================================================
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && echo "Source this file, don't run it directly." && exit 1

require_tool() {
    local NAME="$1" CHECK_CMD="$2" FIX_FUNC="$3"
    if eval "$CHECK_CMD" &>/dev/null; then
        echo -e "${GREEN}✅ $NAME OK${NC}"; return 0
    fi
    echo -e "${YELLOW}⚠️  Missing: $NAME — fixing...${NC}"
    echo -e "${YELLOW}ℹ️  This may require your sudo password.${NC}"
    if declare -f "$FIX_FUNC" >/dev/null 2>&1; then
        "$FIX_FUNC" || { echo -e "${RED}❌ Failed to fix: $NAME${NC}"; return 1; }
    else
        echo -e "${RED}❌ No fix defined for $NAME${NC}"; return 1
    fi
    eval "$CHECK_CMD" &>/dev/null && echo -e "${GREEN}✅ $NAME fixed${NC}" || {
        echo -e "${RED}❌ $NAME still missing after fix attempt${NC}"; return 1
    }
}

# FIX: runs in a subshell anchored to SCRIPT_DIR so cd never affects the parent
fix_llama_bench() {
    (
        cd "$SCRIPT_DIR"
        rm -rf build
        mkdir -p build && cd build && cmake .. && make -j"$(nproc)"
    )
}
fix_python() { sudo apt update && sudo apt install -y python3 python3-pip python3-venv; }
fix_cmake()  { sudo apt update && sudo apt install -y cmake; }
fix_ffmpeg() { sudo apt update && sudo apt install -y ffmpeg; }
fix_bc()     { sudo apt update && sudo apt install -y bc; }
