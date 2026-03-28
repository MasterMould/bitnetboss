#!/bin/bash
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && echo "Source this file, dont run it directly." && exit 1
# ================================================================
# 05-reinstall.sh — Clean deps, source clone, hardware build
# Requires: 00-globals.sh, 02-build.sh
# ================================================================

reinstall_all() {
    echo -e "${YELLOW}⚠️  This will reinstall system dependencies and rebuild BitNet/llama.cpp.${NC}"
    echo -e "${YELLOW}ℹ️  Sudo is required.${NC}"
    read -rp "Continue? [y/N]: " CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Cancelled."; return; }

    # 1. System packages
    sudo apt update && sudo apt install -y \
        git cmake clang-18 llvm-18 libopenblas-dev libomp-dev \
        python3 python3-pip python3-venv bc ffmpeg \
    || { echo -e "${RED}❌ apt install failed${NC}"; return 1; }

    # 2. Clone/copy BitNet source files if CMakeLists.txt is missing
    if [[ ! -f "$SCRIPT_DIR/CMakeLists.txt" ]]; then
        echo -e "${CYAN}📦 BitNet source not found — cloning from $BITNET_REPO ...${NC}"
        local TMP_CLONE
        TMP_CLONE=$(mktemp -d)
        # Clone top-level source only — submodules are handled separately by
        # _ensure_submodules to avoid .git path breakage after cp
        if git clone --depth 1 "$BITNET_REPO" "$TMP_CLONE/bitnet"; then
            cp -r --update=none "$TMP_CLONE/bitnet/." "$SCRIPT_DIR/"
            rm -rf "$TMP_CLONE"
            echo -e "${GREEN}✅ BitNet source copied${NC}"
        else
            rm -rf "$TMP_CLONE"
            echo -e "${RED}❌ git clone failed — check your internet connection${NC}"
            return 1
        fi
    else
        echo -e "${GREEN}✅ Source present ($SCRIPT_DIR/CMakeLists.txt found)${NC}"
        if [[ -f "$SCRIPT_DIR/.git" || -d "$SCRIPT_DIR/.git" ]]; then
            read -rp "Pull latest changes from git? [y/N]: " DO_PULL
            [[ "$DO_PULL" =~ ^[Yy]$ ]] && git -C "$SCRIPT_DIR" pull
        fi
    fi

    # 3. Ensure submodules (llama.cpp etc.) are populated — done separately
    #    so it works whether SCRIPT_DIR is a real git repo or a copied tree
    _ensure_submodules || return 1

    # 4. Hardware-tuned build
    configure_hardware
}
