#!/bin/bash
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && echo "Source this file, dont run it directly." && exit 1
# ================================================================
# 04-models.sh — Model downloader and HuggingFace snapshot helper
# Requires: 00-globals.sh, 03-doctor.sh
# ================================================================

download_models() {
    echo -e "${CYAN}📥 BitNet Model Downloader${NC}"
    echo ""
    echo "  1) BitNet-b1.58-2B-4T        (recommended, wget/curl)"
    echo "  2) BitNet-b1.58-Large        (wget/curl)"
    echo "  3) Falcon3-7B-1.58bit        (HuggingFace snapshot)"
    echo "  4) Llama-3.2-1B-1.58bit      (HuggingFace snapshot)"
    echo "  5) BitNet-2B-4T full repo    (HuggingFace snapshot)"
    echo "  6) Custom URL"
    echo "  0) Cancel"
    read -rp "Choice: " DL_CHOICE

    mkdir -p "$SCRIPT_DIR/models"

    case $DL_CHOICE in
        1) MODEL_URL="https://huggingface.co/microsoft/BitNet-b1.58-2B-4T-gguf/resolve/main/ggml-model-i2_s.gguf"
           MODEL_FILE="$SCRIPT_DIR/models/bitnet-b1.58-2B-4T.gguf" ;;
        2) MODEL_URL="https://huggingface.co/microsoft/bitnet-b1.58-large-gguf/resolve/main/ggml-model-i2_s.gguf"
           MODEL_FILE="$SCRIPT_DIR/models/bitnet-b1.58-large.gguf" ;;
        3) _hf_snapshot_download "tiiuae/Falcon3-7B-1.58bit" "$SCRIPT_DIR/models/Falcon3-7B-1.58bit"; return ;;
        4) _hf_snapshot_download "HF1BitLLM/Llama3-8B-1.58-100B-tokens" "$SCRIPT_DIR/models/Llama3-1bit"; return ;;
        5) _hf_snapshot_download "microsoft/BitNet-b1.58-2B-4T" "$SCRIPT_DIR/models/BitNet-b1.58-2B-4T"; return ;;
        6) read -rp "URL: " MODEL_URL
           read -rp "Save as (e.g. $SCRIPT_DIR/models/my-model.gguf): " MODEL_FILE ;;
        0) return ;;
        *) echo -e "${RED}❌ Invalid choice${NC}"; return 1 ;;
    esac

    if command -v wget &>/dev/null; then
        wget -c --show-progress -O "$MODEL_FILE" "$MODEL_URL"
    elif command -v curl &>/dev/null; then
        curl -L --progress-bar -C - -o "$MODEL_FILE" "$MODEL_URL"
    else
        echo -e "${CYAN}  → Installing wget...${NC}"
        sudo apt install -y wget >>"$LOG_FILE" 2>&1 \
            && wget -c --show-progress -O "$MODEL_FILE" "$MODEL_URL" \
            || { echo -e "${RED}❌ Download unavailable — no wget or curl${NC}"; return 1; }
    fi

    echo -e "${GREEN}✅ Downloaded: $MODEL_FILE${NC}"
    read -rp "Set as default model? [y/N]: " SET_DEFAULT
    [[ "$SET_DEFAULT" =~ ^[Yy]$ ]] && M_PATH="$MODEL_FILE" && \
        echo -e "${GREEN}✅ Default model set to: $M_PATH${NC}"
}

_hf_snapshot_download() {
    local REPO_ID="$1" LOCAL_DIR="$2"
    echo -e "${CYAN}📦 Downloading $REPO_ID via HuggingFace Hub...${NC}"

    # Ensure venv exists
    if [[ ! -x "$VENV_PY" ]]; then
        python3 -m venv "$SCRIPT_DIR/venv" >>"$LOG_FILE" 2>&1
    fi

    # Ensure huggingface_hub is installed — retry once on failure
    "$VENV_PY" -c "import huggingface_hub" &>/dev/null || {
        "$VENV_PIP" install --quiet huggingface_hub hf_transfer >>"$LOG_FILE" 2>&1 || \
        "$VENV_PIP" install huggingface_hub >>"$LOG_FILE" 2>&1
    }

    # If still no huggingface_hub, fall back to wget/curl direct download
    if ! "$VENV_PY" -c "import huggingface_hub" &>/dev/null; then
        echo -e "${YELLOW}  → huggingface_hub unavailable — trying direct wget/curl...${NC}"
        mkdir -p "$LOCAL_DIR"
        local DIRECT_URL="https://huggingface.co/${REPO_ID}/resolve/main/ggml-model-i2_s.gguf"
        local DEST_FILE="$LOCAL_DIR/ggml-model-i2_s.gguf"
        if command -v wget &>/dev/null; then
            wget -c --show-progress -O "$DEST_FILE" "$DIRECT_URL" && \
                echo -e "${GREEN}✅ Downloaded: $DEST_FILE${NC}" || \
                echo -e "${RED}❌ Direct download also failed${NC}"
        elif command -v curl &>/dev/null; then
            curl -L --progress-bar -C - -o "$DEST_FILE" "$DIRECT_URL" && \
                echo -e "${GREEN}✅ Downloaded: $DEST_FILE${NC}" || \
                echo -e "${RED}❌ Direct download also failed${NC}"
        fi
        return
    fi

    mkdir -p "$LOCAL_DIR"
    HF_HUB_ENABLE_HF_TRANSFER=1 "$VENV_PY" - <<PYEOF
from huggingface_hub import snapshot_download
import sys
try:
    path = snapshot_download(
        repo_id="$REPO_ID",
        local_dir="$LOCAL_DIR",
        local_dir_use_symlinks=False,
        ignore_patterns=["*.msgpack","*.h5","*.ot","*.md","*.txt"]
    )
    print(f"Downloaded to: {path}")
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✅ Download complete: $LOCAL_DIR${NC}"
        local FIRST_GGUF
        FIRST_GGUF=$(find "$LOCAL_DIR" -name "*.gguf" | head -1)
        if [[ -n "$FIRST_GGUF" ]]; then
            read -rp "Set $FIRST_GGUF as default model? [y/N]: " SET_DEFAULT
            [[ "$SET_DEFAULT" =~ ^[Yy]$ ]] && M_PATH="$FIRST_GGUF" && \
                echo -e "${GREEN}✅ Default model: $M_PATH${NC}"
        fi
    else
        echo -e "${RED}❌ HuggingFace download failed — see $LOG_FILE${NC}"
    fi
}
