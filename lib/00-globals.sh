#!/bin/bash
# ================================================================
# 00-globals.sh — Path declarations and shared variables
# Sourced first by omni-shield.sh. SCRIPT_DIR is set by the
# entry point before sourcing so all paths resolve correctly
# regardless of which lib file is being executed.
# ================================================================
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && echo "Source this file, don't run it directly." && exit 1

NC='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'

LOG_DIR="$SCRIPT_DIR/chat_logs"
LOG_FILE="$LOG_DIR/system.log"
M_PATH="$SCRIPT_DIR/models/default.gguf"
PLUGIN_DIR="$SCRIPT_DIR/plugins"
MARKET_DIR="$SCRIPT_DIR/marketplace"
BENCH_FILE="$SCRIPT_DIR/.bitnet_benchmark"
LLAMA_BIN="$SCRIPT_DIR/build/bin/llama-bench"
LLAMA_CLI="$SCRIPT_DIR/build/bin/llama-cli"
LLAMA_SERVER="$SCRIPT_DIR/build/bin/llama-server"
VENV_PY="$SCRIPT_DIR/venv/bin/python3"
VENV_PIP="$SCRIPT_DIR/venv/bin/pip"
LLAMA_CPP_REPO="https://github.com/ggerganov/llama.cpp.git"
LLAMA_CPP_DIR="$SCRIPT_DIR/3rdparty/llama.cpp"
BITNET_REPO="https://github.com/microsoft/BitNet.git"
