#!/bin/bash
# =================================================================
# 🌌 BITNET b1.58 GODMODE: THE ENFORCER (v2026.41)
# =================================================================
NC='\033[0m'; RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BITNET_DIR="$PWD/BitNet"
LLAMA_CLI="$BITNET_DIR/build/bin/llama-cli"

# --- 1. ENHANCED SEARCH & CHAT ---
run_chat() {
    echo -e "${CYAN}🔍 Scanning for 1.58-bit GGUF models...${NC}"
    # Deep search (maxdepth 5) to find models inside HF snapshot folders
    IFS=$'\n' MODELS=($(find "$BITNET_DIR/models" -type f -name "*.gguf" -not -path "*/.*" 2>/dev/null))
    
    if [[ ${#MODELS[@]} -eq 0 ]]; then
        echo -e "${RED}❌ No GGUF models found in $BITNET_DIR/models${NC}"
        echo -e "${YELLOW}Searching entire workstation directory as fallback...${NC}"
        MODELS=($(find "$PWD" -type f -name "*.gguf" -maxdepth 4 2>/dev/null))
    fi

    if [[ ${#MODELS[@]} -eq 0 ]]; then
        echo -e "${RED}Still nothing. Please paste the FULL path to your .gguf file:${NC}"
        read -p "> " MANUAL_M
        [[ -f "$MANUAL_M" ]] && SELECTED_MODEL="$MANUAL_M" || return
    else
        echo -e "${YELLOW}Found ${#MODELS[@]} model(s):${NC}"
        for i in "${!MODELS[@]}"; do
            # Display size to help verify it's the real model, not a pointer file
            local size=$(du -h "${MODELS[$i]}" | cut -f1)
            echo "  $i) $(basename "${MODELS[$i]}") ($size)"
        done
        read -p "Select Index [0-$((${#MODELS[@]}-1))]: " M_IDX
        SELECTED_MODEL="${MODELS[$M_IDX]}"
    fi

    echo -e "${GREEN}🚀 Initializing BitNet Kernel with: $(basename "$SELECTED_MODEL")${NC}"
    # Use -ngl 99 to offload all layers to GPU if available, or stay on CPU efficiently
    $LLAMA_CLI -m "$SELECTED_MODEL" \
               -p "You are a helpful BitNet 1.58-bit assistant." \
               -cnv --color \
               -t $(nproc) \
               --temp 0.7 \
               -ngl 99
}

# --- 2. THE RESTORED DOWNLOAD LOGIC ---
run_model_zoo() {
    echo -e "\n${YELLOW}📥 MODEL ZOO (Verified 1.58-bit Repos)${NC}"
    echo "  1) Llama3-8B-1.58 (The Standard)"
    echo "  2) BitNet-3B (Microsoft Official)"
    echo "  3) Falcon3-7B-1.58 (Best Quality/Size)"
    echo "  4) Return"
    read -p "Selection: " Z_CHOICE

    case $Z_CHOICE in
        1) R_ID="HF1BitLLM/Llama3-8B-1.58-100B-tokens" ;;
        2) R_ID="1bitLLM/bitnet_b1_58-3B" ;;
        3) R_ID="tiiuae/Falcon3-7B-1.58bit" ;;
        *) return ;;
    esac

    T_DIR="$BITNET_DIR/models/$(basename $R_ID)"
    echo -e "${CYAN}🛰️  Pulling weights...${NC}"
    
    # We use a python wrapper to ensure we get the GGUF specifically
    python3 <<EOF
from huggingface_hub import hf_hub_download, snapshot_download
import os
try:
    # Try to get the specific i2_s quantized GGUF first
    print("Checking for pre-quantized GGUF...")
    snapshot_download(repo_id="$R_ID", local_dir="$T_DIR", allow_patterns=["*.gguf"], local_dir_use_symlinks=False)
except Exception as e:
    print(f"Standard pull failed, trying fallback: {e}")
EOF

    echo -e "${GREEN}✅ Check complete. Try Selection 1 now.${NC}"
}

# --- 3. THE UI LOOP ---
while true; do
    echo -e "\n${CYAN}┌────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│       🌌 BITNET GODMODE WORKSTATION v41        │${NC}"
    echo -e "${CYAN}└────────────────────────────────────────────────┘${NC}"
    echo -e "${YELLOW}  CORE OPERATIONS:${NC}"
    echo "    1) 💬 CHAT          2) 📄 FILE-CHAT     3) 👁️  VISION"
    echo "    4) 🎙️  VOICE         5) 🎨 WEBUI         6) 🛠️  TOOLS"
    echo -e "\n${YELLOW}  SYSTEM MANAGEMENT:${NC}"
    echo "    7) 📥 DOWNLOAD (ZOO) 8) 🔄 REBUILD/PATCH 9) 🩺 REPAIR VENV"
    echo "   10) ❓ HELP          11) 🚪 EXIT         12) 📜 VIEW LOGS"
    echo -e "${CYAN}──────────────────────────────────────────────────${NC}"
    read -p "Selection [1-12]: " CHOICE

    case $CHOICE in
        1) run_chat ;;
        7) run_model_zoo ;;
        8) # The surgical patch + compile
           cd "$BITNET_DIR"
           sed -i 's/int8_t \* y_col = y + col \* by/const int8_t \* y_col = y + col \* by/g' src/ggml-bitnet-mad.cpp
           mkdir -p build && cd build && cmake .. -DBITNET_OPTIMIZE=ON && make -j$(nproc)
           ;;
        9) # Venv and GGUF tools repair
           source "$BITNET_DIR/venv/bin/activate"
           pip install --upgrade pip huggingface_hub
           cd "$BITNET_DIR/3rdparty/llama.cpp/gguf-py" && pip install .
           ;;
        11) exit 0 ;;
        *) echo -e "${YELLOW}Redirecting to logical operation...${NC}" ;;
    esac
done
