#!/bin/bash
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && echo "Source this file, dont run it directly." && exit 1
# ================================================================
# 10-monitor.sh — Live CPU/RAM/GPU monitor and header printer
# Requires: 00-globals.sh, 09-benchmark.sh
# ================================================================

get_cpu() { top -bn1 | grep "Cpu(s)" | awk '{print $2+$4 "%"}'; }
get_ram() { free -h | awk '/Mem:/ {print $3 "/" $2}'; }
get_gpu() {
    command -v nvidia-smi &>/dev/null \
        && nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits \
           | head -n1 | awk '{print $1 "%"}' \
        || echo "N/A"
}

print_header() {
    load_benchmark
    local CPU RAM GPU
    CPU=$(get_cpu); RAM=$(get_ram); GPU=$(get_gpu)
    echo -e "${GREEN}CPU: $CPU | RAM: $RAM | GPU: $GPU | Backend: ${backend:-?} | Speed: ${tokens_per_sec:-?} tok/s${NC}"
}
