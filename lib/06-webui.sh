#!/bin/bash
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && echo "Source this file, dont run it directly." && exit 1
# ================================================================
# 06-webui.sh — Open WebUI + llama-server launcher
# Requires: 00-globals.sh, 02-build.sh
# ================================================================

launch_webui() {
    if [[ ! -f "$LLAMA_SERVER" ]]; then
        echo -e "${CYAN}🔨 llama-server not found — building now...${NC}"
        configure_hardware || return 1
    fi
    if [[ ! -f "$LLAMA_SERVER" ]]; then
        echo -e "${RED}❌ Build completed but llama-server still not found at $LLAMA_SERVER${NC}"
        return 1
    fi
    echo -e "${CYAN}🌐 Starting llama-server on :8080...${NC}"
    "$LLAMA_SERVER" -m "$M_PATH" --port 8080 &
    LLAMA_SERVER_PID=$!
    echo -e "${GREEN}✅ llama-server running (PID: $LLAMA_SERVER_PID)${NC}"
    if command -v open-webui &>/dev/null; then
        open-webui serve
    else
        echo -e "${CYAN}  → open-webui not found — installing...${NC}"
        "$VENV_PIP" install --quiet open-webui >>"$LOG_FILE" 2>&1 \
            && open-webui serve \
            || echo -e "${YELLOW}  → open-webui install failed — llama-server is live at http://localhost:8080${NC}"
    fi
}
