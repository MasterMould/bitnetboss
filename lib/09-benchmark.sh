#!/bin/bash
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && echo "Source this file, dont run it directly." && exit 1
# ================================================================
# 09-benchmark.sh — Backend benchmark and result caching
# Requires: 00-globals.sh, 01-deps.sh, 02-build.sh
# ================================================================

run_benchmark() {
    # Auto-build if llama-bench is missing
    if [[ ! -f "$LLAMA_BIN" ]]; then
        echo -e "${CYAN}⚡ llama-bench not found — building...${NC}"
        configure_hardware || return 1
    fi
    require_tool "bc" "command -v bc" fix_bc || return 1

    local BEST="CPU" SCORE=0

    test_backend() {
        local BNAME="$1" CMD="$2"
        local OUT TOK
        OUT=$(eval "$CMD" 2>/dev/null || true)
        TOK=$(echo "$OUT" | grep -i tok/s | awk '{print $(NF-1)}' | head -n1)
        TOK=${TOK:-0}
        if (( $(echo "$TOK > $SCORE" | bc -l) )); then SCORE="$TOK"; BEST="$BNAME"; fi
    }

    echo -e "${CYAN}⚡ Running benchmark...${NC}"
    test_backend "CPU"  "$LLAMA_BIN -m $M_PATH -t $(nproc) -n 64"
    command -v nvidia-smi &>/dev/null && test_backend "CUDA" "$LLAMA_BIN -m $M_PATH -ngl 999 -n 64"

    { echo "backend=$BEST"; echo "tokens_per_sec=$SCORE"; } > "$BENCH_FILE"
    echo -e "${GREEN}✅ Best backend: $BEST @ ${SCORE} tok/s${NC}"
}

load_benchmark() { [[ -f "$BENCH_FILE" ]] && source "$BENCH_FILE"; }
