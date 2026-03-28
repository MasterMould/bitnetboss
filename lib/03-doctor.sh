#!/bin/bash
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && echo "Source this file, dont run it directly." && exit 1
# ================================================================
# 03-doctor.sh — System audit, auto-repair, help system
# Requires: 00-globals.sh, 01-deps.sh, 02-build.sh
# ================================================================

run_doctor() {
    echo -e "${CYAN}🩺 BitNet Doctor: Auditing System Health...${NC}"
    echo -e "${YELLOW}ℹ️  Some fixes require sudo and a session restart to take effect.${NC}"

    # 1. Check user groups required for GPU access
    for GRP in "video" "render"; do
        if ! groups "$USER" | grep -qw "$GRP"; then
            echo -e "${YELLOW}⚠️  User not in '$GRP' group (required for GPU access).${NC}"
            sudo usermod -aG "$GRP" "$USER"
            echo -e "${GREEN}✅ Fixed: Added $USER to $GRP. Log out and back in to apply.${NC}"
        else
            echo -e "${GREEN}✅ Group '$GRP' OK${NC}"
        fi
    done

    # 2. Check GPU drivers & toolkits — auto-install what we can
    local GPU_LINES
    GPU_LINES=$(lspci | grep -iE "VGA|3D controller|Display controller")

    if command -v nvidia-smi &>/dev/null; then
        echo -e "${GREEN}✅ NVIDIA driver: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1)${NC}"
    elif echo "$GPU_LINES" | grep -iq "Intel"; then
        if [[ ! -d "/opt/intel/oneapi" ]]; then
            echo -e "${CYAN}  → Intel oneAPI not found — attempting install...${NC}"
            sudo apt install -y intel-oneapi-compiler-dpcpp-cpp intel-oneapi-mkl >>"$LOG_FILE" 2>&1 \
                && echo -e "${GREEN}✅ Intel oneAPI installed${NC}" \
                || echo -e "${YELLOW}⚠️  oneAPI install incomplete — run Reinstall for full setup${NC}"
        else
            echo -e "${GREEN}✅ Intel oneAPI found${NC}"
        fi
        echo "$GPU_LINES" | grep -iqE "AMD|ATI|Radeon" && \
            echo -e "${CYAN}ℹ️  AMD iGPU also present — Intel Arc takes priority${NC}"
    elif echo "$GPU_LINES" | grep -iqE "AMD|ATI|Radeon"; then
        if [[ ! -f "/opt/rocm/bin/rocminfo" ]]; then
            echo -e "${CYAN}  → AMD ROCm not found — attempting install...${NC}"
            sudo apt install -y rocm-dev >>"$LOG_FILE" 2>&1 \
                && echo -e "${GREEN}✅ ROCm installed${NC}" \
                || echo -e "${YELLOW}⚠️  ROCm install failed — run Reinstall for manual ROCm setup${NC}"
        else
            echo -e "${GREEN}✅ AMD ROCm found${NC}"
        fi
    else
        echo -e "${CYAN}ℹ️  No discrete GPU — CPU-only mode${NC}"
    fi

    # 3. Python virtual environment + required packages
    if [[ ! -d "$SCRIPT_DIR/venv" ]]; then
        echo -e "${YELLOW}⚙️  No venv found — creating...${NC}"
        python3 -m venv "$SCRIPT_DIR/venv" && \
            "$VENV_PIP" install --quiet --upgrade pip && \
            echo -e "${GREEN}✅ venv created${NC}" || \
            echo -e "${RED}❌ venv creation failed${NC}"
    else
        echo -e "${GREEN}✅ Python venv present${NC}"
    fi

    # Ensure required packages are installed in the venv
    if [[ -x "$VENV_PY" ]]; then
        local MISSING_PKGS=()
        for pkg in huggingface_hub hf_transfer numpy tqdm; do
            "$VENV_PY" -c "import ${pkg//-/_}" &>/dev/null || MISSING_PKGS+=("$pkg")
        done
        if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
            echo -e "${YELLOW}  → Installing missing packages: ${MISSING_PKGS[*]}${NC}"
            "$VENV_PIP" install --quiet "${MISSING_PKGS[@]}" && \
                echo -e "${GREEN}✅ Packages installed${NC}" || \
                echo -e "${RED}❌ Package install failed${NC}"
        else
            echo -e "${GREEN}✅ venv packages OK${NC}"
        fi
    fi

    # 4. llama-bench binary — auto-build if missing
    if [[ -f "$LLAMA_BIN" ]]; then
        echo -e "${GREEN}✅ llama-bench binary found${NC}"
    else
        echo -e "${CYAN}  → llama-bench not found — building...${NC}"
        configure_hardware
        [[ -f "$LLAMA_BIN" ]] \
            && echo -e "${GREEN}✅ llama-bench built${NC}" \
            || echo -e "${YELLOW}⚠️  Build did not produce llama-bench — check Logs${NC}"
    fi

    echo -e "${GREEN}✨ Audit complete.${NC}"
}

# ================================================================
# ❓ INTEGRATED HELP SYSTEM
# ================================================================
display_help() {
    local HELP_FILE="$LOG_DIR/help_system.txt"
    cat << 'EOF' > "$HELP_FILE"
==================================================
🆘 BITNET OMNI-HELP & TROUBLESHOOTING
==================================================
INTEL ARC A770:
- Requires oneAPI. Run: source /opt/intel/oneapi/setvars.sh
- Ensure 'icpx' is in your PATH.
- Build flag used: -DGGML_SYCL=ON -DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx

AMD RX 570 (POLARIS):
- Requires ROCm 6.x.
- Override gfx version if needed: export HSA_OVERRIDE_GFX_VERSION=8.0.3
- Build flag used: -DGGML_HIPBLAS=ON -DAMDGPU_TARGETS=gfx803

NVIDIA:
- Requires CUDA toolkit installed.
- Build flag used: -DGGML_CUDA=ON

COMMON FIXES:
- Permission Denied on GPU : Run Doctor or:
    sudo usermod -aG render $USER  && REBOOT
- Slow inference           : Check AVX-512 is enabled in BIOS.
- Benchmark/build fails    : Use Reinstall then re-run Benchmark.
- venv broken              : Run Doctor to auto-rebuild.
- Logs                     : ./chat_logs/history.log  (session archives)
                             ./chat_logs/system.log   (system log)

PLUGIN SYSTEM:
- Add a plugin  : place a .sh file in ./plugins/
- Marketplace   : place a .sh file in ./marketplace/ then use Install option
- Plugin format :
    #@name: My Plugin
    #@desc: What it does
    #@deps: python ffmpeg llama bc

MODEL DOWNLOADS:
- Place .gguf model files in ./models/
- Default model path: ./models/default.gguf
==================================================
EOF
    less "$HELP_FILE"
}
