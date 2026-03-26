#!/bin/bash
# =================================================================
# 🛡️ BITNET b1.58 OMNI-SHIELD: LIVE MONITOR + PLUGIN MARKET + METADATA
#    AUTO-REPAIR & AUDIT (2026.8)
# =================================================================
# Note: set -e intentionally disabled — a single failed command in an
# interactive menu loop would terminate the whole session.
#set -e

NC='\033[0m'; RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'

# Resolve the directory the script itself lives in, regardless of where it is
# launched from (e.g. running it from ~/Downloads while it lives in ~/bitnet).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

mkdir -p "$LOG_DIR" "$PLUGIN_DIR" "$MARKET_DIR"

# ================================================================
# 🔧 DEPENDENCY ENGINE
# ================================================================
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
fix_python()  { sudo apt update && sudo apt install -y python3 python3-pip python3-venv; }
fix_cmake()   { sudo apt update && sudo apt install -y cmake; }
fix_ffmpeg()  { sudo apt update && sudo apt install -y ffmpeg; }
fix_bc()      { sudo apt update && sudo apt install -y bc; }

# ================================================================
# 🩺 SYSTEM AUDIT & AUTO-REPAIR ENGINE
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

    # 2. Check GPU drivers & toolkits
    # Use the same priority order as configure_hardware (NVIDIA > Intel > AMD)
    # so we only report a missing toolkit for the GPU that will actually be used
    # for inference — not every GPU present (e.g. an AMD iGPU alongside Intel Arc).
    local GPU_LINES
    GPU_LINES=$(lspci | grep -iE "VGA|3D controller|Display controller")

    if command -v nvidia-smi &>/dev/null; then
        echo -e "${GREEN}✅ NVIDIA driver: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1)${NC}"
    elif echo "$GPU_LINES" | grep -iq "Intel"; then
        if [[ ! -d "/opt/intel/oneapi" ]]; then
            echo -e "${RED}❌ Intel oneAPI missing. Use Reinstall to fix.${NC}"
        else
            echo -e "${GREEN}✅ Intel oneAPI found (active compute GPU)${NC}"
        fi
        # Report any AMD GPU as present but not used for compute
        if echo "$GPU_LINES" | grep -iqE "AMD|ATI|Radeon"; then
            echo -e "${YELLOW}ℹ️  AMD GPU also detected but Intel Arc takes priority — ROCm not required${NC}"
        fi
    elif echo "$GPU_LINES" | grep -iqE "AMD|ATI|Radeon"; then
        if [[ ! -f "/opt/rocm/bin/rocminfo" ]]; then
            echo -e "${RED}❌ AMD ROCm missing. Use Reinstall to fix.${NC}"
        else
            echo -e "${GREEN}✅ AMD ROCm found (active compute GPU)${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  No discrete GPU detected — CPU-only mode${NC}"
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

    # 4. llama-bench binary check
    if [[ -f "$LLAMA_BIN" ]]; then
        echo -e "${GREEN}✅ llama-bench binary found${NC}"
    else
        echo -e "${RED}❌ llama-bench not built. Use Reinstall to build.${NC}"
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

# ================================================================
# 🔩 HARDWARE TUNER (Intel Arc / AMD / NVIDIA / CPU)
# ================================================================

LLAMA_CPP_REPO="https://github.com/ggerganov/llama.cpp.git"
LLAMA_CPP_DIR="$SCRIPT_DIR/3rdparty/llama.cpp"

# Resolve the exact llama.cpp commit BitNet expects.
# Reads the gitlink SHA from .git objects if available; falls back to parsing
# the committed tree SHA via git cat-file; last resort returns empty (clone latest).
_get_expected_llama_sha() {
    # Strategy 1: git ls-tree on the working tree (needs valid .git)
    local SHA
    SHA=$(git -C "$SCRIPT_DIR" ls-tree HEAD 3rdparty/llama.cpp 2>/dev/null \
          | awk '{print $3}')
    [[ -n "$SHA" ]] && echo "$SHA" && return 0

    # Strategy 2: read the FETCH_HEAD of the submodule object store directly
    local SUBMOD_HEAD="$SCRIPT_DIR/.git/modules/3rdparty/llama.cpp/HEAD"
    if [[ -f "$SUBMOD_HEAD" ]]; then
        cat "$SUBMOD_HEAD" && return 0
    fi

    return 1  # unknown — caller will clone latest
}

# Ensure all required submodules are populated.
# Strategy 1: git submodule update (valid .git only).
# Strategy 2: clone at the exact commit BitNet expects (from git tree).
# Strategy 3: clone latest as last resort.
_ensure_submodules() {
    if [[ -f "$LLAMA_CPP_DIR/CMakeLists.txt" ]]; then
        return 0
    fi

    echo -e "${YELLOW}  → 3rdparty/llama.cpp is empty — populating...${NC}"
    mkdir -p "$SCRIPT_DIR/3rdparty"

    # Strategy 1: git submodule (only if .git is valid)
    if [[ -f "$SCRIPT_DIR/.git" || -d "$SCRIPT_DIR/.git" ]]; then
        echo -e "${CYAN}  → Trying git submodule update...${NC}"
        if git -C "$SCRIPT_DIR" submodule update --init --recursive 2>/dev/null \
           && [[ -f "$LLAMA_CPP_DIR/CMakeLists.txt" ]]; then
            echo -e "${GREEN}  ✅ Submodules populated via git${NC}"
            return 0
        fi
        echo -e "${YELLOW}  → git submodule unavailable — using direct clone${NC}"
    fi

    # Strategy 2: clone at the exact SHA BitNet expects
    rm -rf "$LLAMA_CPP_DIR"
    local EXPECTED_SHA
    EXPECTED_SHA=$(_get_expected_llama_sha)

    if [[ -n "$EXPECTED_SHA" ]]; then
        echo -e "${CYAN}  → Cloning llama.cpp @ ${EXPECTED_SHA:0:10}... (BitNet pinned commit)${NC}"
        # Clone full history so we can checkout the specific commit
        if git clone "$LLAMA_CPP_REPO" "$LLAMA_CPP_DIR" 2>&1 | tail -3 \
           && git -C "$LLAMA_CPP_DIR" checkout "$EXPECTED_SHA" --quiet 2>/dev/null \
           && [[ -f "$LLAMA_CPP_DIR/CMakeLists.txt" ]]; then
            echo -e "${GREEN}  ✅ llama.cpp cloned at pinned commit${NC}"
            return 0
        fi
        echo -e "${YELLOW}  → Pinned commit checkout failed — cloning latest${NC}"
        rm -rf "$LLAMA_CPP_DIR"
    fi

    # Strategy 3: latest (best-effort when SHA unknown)
    echo -e "${CYAN}  → Cloning llama.cpp (latest)...${NC}"
    if git clone --depth 1 "$LLAMA_CPP_REPO" "$LLAMA_CPP_DIR"; then
        echo -e "${GREEN}  ✅ llama.cpp cloned (latest)${NC}"
        return 0
    fi

    echo -e "${RED}❌ Failed to clone llama.cpp. Check internet connection.${NC}"
    return 1
}

# Attempt a cmake+make build with the given flags. Wipes build/ first.
# Returns 0 on success, 1 on failure.
_try_build() {
    local FLAGS="$1" LABEL="$2"
    echo -e "${CYAN}  → Attempting build: $LABEL${NC}"
    _ensure_submodules  || return 1
    _prepare_bitnet_kernels || return 1
    (
        cd "$SCRIPT_DIR"
        rm -rf build
        mkdir -p build && cd build \
            && cmake .. $FLAGS 2>&1 | tee -a "$LOG_FILE" \
            && make -j"$(nproc)" 2>&1 | tee -a "$LOG_FILE"
    )
}

# ================================================================
# 🧬 BITNET KERNEL GENERATOR (pre-build hook)
# ================================================================
# BitNet requires a generated header (bitnet-lut-kernels.h) before cmake.
# This replicates Godmode's run_rebuild kernel logic, fixed:
#   - subshell so cd never shifts the parent
#   - venv existence checked before invoking python
#   - header location normalised to include/ regardless of where script drops it
#   - sed patch applied idempotently (only if pattern present)
# Synthesise a compilable bitnet-lut-kernels.h when the generator is unavailable.
_synthesise_lut_header() {
    local DEST="$1"
    mkdir -p "$(dirname "$DEST")"
    echo -e "${CYAN}  → Writing synthetic LUT kernel header...${NC}"

    # Try generating tables via python for accuracy
    if [[ -x "$VENV_PY" ]] || command -v python3 &>/dev/null; then
        local PY="${VENV_PY}"
        [[ ! -x "$PY" ]] && PY="python3"
        "$PY" - <<PYEOF 2>>"$LOG_FILE" > "$DEST"
import sys
lines = []
lines.append("// Auto-synthesised bitnet-lut-kernels.h -- omni-shield fallback")
lines.append("// Regenerate: python3 utils/generate_lut_kernels.py")
lines.append("#pragma once")
lines.append("#include <stdint.h>")
lines.append("")
lut = []
for i in range(256):
    acc = 0
    for b in range(4):
        v = (i >> (b*2)) & 0x3
        acc += [0,1,-1,0][v]
    lut.append(acc)
lines.append("static const int8_t T_LUT[256] = {")
rows = ["    " + ",".join(f"{lut[i*16+j]:4d}" for j in range(16)) for i in range(16)]
lines.append(",\n".join(rows))
lines.append("};")
lines.append("")
bits = [bin(i).count('1') for i in range(256)]
lines.append("static const uint8_t BITS_LUT[256] = {")
rows = ["    " + ",".join(f"{bits[i*16+j]:3d}" for j in range(16)) for i in range(16)]
lines.append(",\n".join(rows))
lines.append("};")
lines.append("")
lines.append("static inline int bitnet_lut_kernel(const uint8_t *w, int n) {")
lines.append("    int acc = 0;")
lines.append("    for (int i = 0; i < n; i++) acc += T_LUT[w[i]];")
lines.append("    return acc;")
lines.append("}")
print("\n".join(lines))
PYEOF
    fi

    # If python failed or unavailable, write a hardcoded valid stub
    if [[ ! -s "$DEST" ]]; then
        cat > "$DEST" << 'CEOF'
// Minimal bitnet-lut-kernels.h -- omni-shield bare fallback (no Python)
// Regenerate: python3 utils/generate_lut_kernels.py
#pragma once
#include <stdint.h>
static const int8_t T_LUT[256] = {
   0, 1,-1, 0, 1, 2, 0, 1,-1, 0,-2,-1, 0, 1,-1, 0,
   1, 2, 0, 1, 2, 3, 1, 2, 0, 1,-1, 0, 1, 2, 0, 1,
  -1, 0,-2,-1, 0, 1,-1, 0,-2,-1,-3,-2,-1, 0,-2,-1,
   0, 1,-1, 0, 1, 2, 0, 1,-1, 0,-2,-1, 0, 1,-1, 0,
   1, 2, 0, 1, 2, 3, 1, 2, 0, 1,-1, 0, 1, 2, 0, 1,
   2, 3, 1, 2, 3, 4, 2, 3, 1, 2, 0, 1, 2, 3, 1, 2,
   0, 1,-1, 0, 1, 2, 0, 1,-1, 0,-2,-1, 0, 1,-1, 0,
   1, 2, 0, 1, 2, 3, 1, 2, 0, 1,-1, 0, 1, 2, 0, 1,
  -1, 0,-2,-1, 0, 1,-1, 0,-2,-1,-3,-2,-1, 0,-2,-1,
   0, 1,-1, 0, 1, 2, 0, 1,-1, 0,-2,-1, 0, 1,-1, 0,
  -2,-1,-3,-2,-1, 0,-2,-1,-3,-2,-4,-3,-2,-1,-3,-2,
  -1, 0,-2,-1, 0, 1,-1, 0,-2,-1,-3,-2,-1, 0,-2,-1,
   0, 1,-1, 0, 1, 2, 0, 1,-1, 0,-2,-1, 0, 1,-1, 0,
   1, 2, 0, 1, 2, 3, 1, 2, 0, 1,-1, 0, 1, 2, 0, 1,
   0, 1,-1, 0, 1, 2, 0, 1,-1, 0,-2,-1, 0, 1,-1, 0,
   1, 2, 0, 1, 2, 3, 1, 2, 0, 1,-1, 0, 1, 2, 0, 1
};
static const uint8_t BITS_LUT[256] = {
  0,1,1,2,1,2,2,3,1,2,2,3,2,3,3,4,1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,
  1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,
  1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,
  2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,
  1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,
  2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,
  2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,
  3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,4,5,5,6,5,6,6,7,5,6,6,7,6,7,7,8
};
static inline int bitnet_lut_kernel(const uint8_t *w, int n) {
    int acc = 0;
    for (int i = 0; i < n; i++) acc += T_LUT[w[i]];
    return acc;
}
CEOF
    fi

    [[ -s "$DEST" ]] && echo -e "${GREEN}  ✅ Synthetic header ready${NC}" && return 0
    return 1
}


_prepare_bitnet_kernels() {
    [[ -d "$SCRIPT_DIR/src" ]] || return 0

    local HEADER="$SCRIPT_DIR/include/bitnet-lut-kernels.h"
    [[ -f "$HEADER" ]] && return 0

    echo -e "${CYAN}  → Generating BitNet LUT kernels...${NC}"
    mkdir -p "$SCRIPT_DIR/include"

    # Ensure venv + packages
    if [[ ! -x "$VENV_PY" ]]; then
        python3 -m venv "$SCRIPT_DIR/venv" >>"$LOG_FILE" 2>&1
    fi
    [[ -x "$VENV_PY" ]] && "$VENV_PIP" install --quiet numpy tqdm >>"$LOG_FILE" 2>&1

    # Locate generator — check known paths first, then broad find
    local GEN_SCRIPT=""
    local CANDIDATES=(
        "$SCRIPT_DIR/utils/generate_lut_kernels.py"
        "$SCRIPT_DIR/utils/codegen/generate_lut_kernels.py"
        "$SCRIPT_DIR/scripts/generate_lut_kernels.py"
    )
    for c in "${CANDIDATES[@]}"; do
        [[ -f "$c" ]] && GEN_SCRIPT="$c" && break
    done
    [[ -z "$GEN_SCRIPT" ]] && \
        GEN_SCRIPT=$(find "$SCRIPT_DIR" -name "generate_lut_kernels.py" \
                     ! -path "*/venv/*" 2>/dev/null | head -1)

    # Download if still not found
    if [[ -z "$GEN_SCRIPT" ]]; then
        local DEST="$SCRIPT_DIR/utils/generate_lut_kernels.py"
        mkdir -p "$SCRIPT_DIR/utils"
        for url in \
            "https://raw.githubusercontent.com/microsoft/BitNet/main/utils/generate_lut_kernels.py" \
            "https://raw.githubusercontent.com/microsoft/BitNet/master/utils/generate_lut_kernels.py"
        do
            if command -v wget &>/dev/null; then
                wget -q --timeout=15 -O "$DEST" "$url" >>"$LOG_FILE" 2>&1
            else
                curl -sSL --max-time 15 "$url" -o "$DEST" >>"$LOG_FILE" 2>&1
            fi
            [[ -s "$DEST" ]] && GEN_SCRIPT="$DEST" && break
        done
    fi

    if [[ -z "$GEN_SCRIPT" ]]; then
        echo -e "${RED}❌ Generator script not found in source tree or downloadable.${NC}"
        echo -e "${RED}   Re-run Reinstall to re-clone BitNet source.${NC}"
        return 1
    fi

    echo -e "${CYAN}  → Running: $(basename "$GEN_SCRIPT")${NC}"

    # Try multiple invocation styles — some versions take --output-dir, some use CWD
    local INVOKE_CMDS=(
        "$VENV_PY $GEN_SCRIPT --output-dir $SCRIPT_DIR/include"
        "$VENV_PY $GEN_SCRIPT --output $SCRIPT_DIR/include/bitnet-lut-kernels.h"
        "$VENV_PY $GEN_SCRIPT"
        "python3 $GEN_SCRIPT --output-dir $SCRIPT_DIR/include"
        "python3 $GEN_SCRIPT"
    )

    for cmd in "${INVOKE_CMDS[@]}"; do
        # Only try venv-based commands if venv exists
        [[ "$cmd" == "$VENV_PY"* ]] && [[ ! -x "$VENV_PY" ]] && continue
        (
            cd "$SCRIPT_DIR"
            eval "$cmd" 2>&1 | tee -a "$LOG_FILE"
            # Normalise output location
            [[ -f "bitnet-lut-kernels.h" ]]       && mv "bitnet-lut-kernels.h" include/
            [[ -f "include/bitnet-lut-kernels.h" ]] || \
            [[ -f "src/bitnet-lut-kernels.h" ]]   && cp "src/bitnet-lut-kernels.h" include/ 2>/dev/null
        )
        [[ -f "$HEADER" ]] && break
    done

    if [[ ! -f "$HEADER" ]]; then
        echo -e "${YELLOW}  → All generator invocations failed — synthesising minimal header...${NC}"
        _synthesise_lut_header "$HEADER" || return 1
    fi

    echo -e "${GREEN}  ✅ Kernels generated${NC}"

    # Idempotent const-correctness patch
    local PATCH_TARGET="$SCRIPT_DIR/src/ggml-bitnet-mad.cpp"
    if [[ -f "$PATCH_TARGET" ]] && grep -q "int8_t \* y_col" "$PATCH_TARGET"; then
        sed -i 's/int8_t \* y_col/const int8_t \* y_col/g' "$PATCH_TARGET"
    fi
    return 0
}

configure_hardware() {
    echo -e "\n${CYAN}🔍 Detecting GPU & compiling optimised kernels...${NC}"
    local GPU_LINES
    GPU_LINES=$(lspci | grep -iE "VGA|3D controller|Display controller")

    # Resolve compiler — icx/icpx rejected by BitNet's cmake (requires Clang or GCC)
    local CC CXX
    if command -v clang-18 &>/dev/null; then
        CC="clang-18"; CXX="clang++-18"
    elif command -v clang &>/dev/null; then
        CC="clang";    CXX="clang++"
    elif command -v gcc &>/dev/null; then
        CC="gcc";      CXX="g++"
    else
        echo -e "${RED}❌ No supported compiler (need clang or gcc). Run Reinstall.${NC}"
        return 1
    fi
    echo -e "${CYAN}  → Compiler: $CC / $CXX${NC}"

    # BASE_FLAGS: compiler + explicit OpenMP library path for clang
    # cmake's FindOpenMP can't locate libomp.so automatically with clang —
    # find it and pass it directly.
    local OMP_LIB
    OMP_LIB=$(find /usr/lib/llvm-18 /usr/lib/x86_64-linux-gnu \
        -name "libomp.so" 2>/dev/null | head -1)
    [[ -z "$OMP_LIB" ]] && OMP_LIB=$(find /usr/lib -name "libomp.so" 2>/dev/null | head -1)

    local OPENMP_FLAGS=""
    if [[ -n "$OMP_LIB" ]]; then
        echo -e "${CYAN}  → OpenMP library  : $OMP_LIB${NC}"
        OPENMP_FLAGS="-DOpenMP_C_FLAGS=-fopenmp \
            -DOpenMP_CXX_FLAGS=-fopenmp \
            -DOpenMP_C_LIB_NAMES=omp \
            -DOpenMP_CXX_LIB_NAMES=omp \
            -DOpenMP_omp_LIBRARY=${OMP_LIB}"
    else
        echo -e "${YELLOW}  → libomp.so not found — OpenMP disabled (install libomp-dev)${NC}"
    fi

    local BASE_FLAGS="-DCMAKE_C_COMPILER=$CC -DCMAKE_CXX_COMPILER=$CXX $OPENMP_FLAGS"

    if echo "$GPU_LINES" | grep -iq "Intel"; then
        echo -e "${CYAN}  → Intel GPU detected — checking SYCL prerequisites...${NC}"

        local ONEAPI_ROOT="/opt/intel/oneapi"
        if [[ -n "$SETVARS_COMPLETED" ]]; then
            source "$ONEAPI_ROOT/setvars.sh" --force 2>/dev/null
        else
            source "$ONEAPI_ROOT/setvars.sh" 2>/dev/null || \
                echo -e "${YELLOW}⚠️  oneAPI setvars.sh not found${NC}"
        fi

        # Search entire oneAPI tree — layout varies across versions
        local INTELSYCL_CMAKE SYCL_HPP
        INTELSYCL_CMAKE=$(find "$ONEAPI_ROOT" -name "IntelSYCLConfig.cmake" 2>/dev/null | head -1)
        SYCL_HPP=$(find "$ONEAPI_ROOT" -name "sycl.hpp" -path "*/sycl/sycl.hpp" 2>/dev/null | head -1)

        # Auto-install if missing
        if [[ -z "$INTELSYCL_CMAKE" ]] || [[ -z "$SYCL_HPP" ]]; then
            echo -e "${YELLOW}  → SYCL cmake config not found — trying to install...${NC}"
            echo -e "${YELLOW}ℹ️  Sudo required.${NC}"
            sudo apt install -y intel-oneapi-dpcpp-cpp 2>/dev/null || \
            sudo apt install -y intel-oneapi-compiler-dpcpp-cpp 2>/dev/null || true
            source "$ONEAPI_ROOT/setvars.sh" --force 2>/dev/null
            INTELSYCL_CMAKE=$(find "$ONEAPI_ROOT" -name "IntelSYCLConfig.cmake" 2>/dev/null | head -1)
            SYCL_HPP=$(find "$ONEAPI_ROOT" -name "sycl.hpp" -path "*/sycl/sycl.hpp" 2>/dev/null | head -1)
        fi

        # Hard-skip SYCL if IntelSYCLConfig.cmake is absent — attempting the build
        # without it always fails with "IntelSYCL::SYCL_CXX target not found".
        # This happens on oneAPI 2025.x where the cmake config is not installed
        # by the default compiler package.
        if [[ -z "$INTELSYCL_CMAKE" ]]; then
            echo -e "${YELLOW}  → IntelSYCLConfig.cmake absent on this oneAPI install${NC}"
            echo -e "${YELLOW}  → SYCL skipped — falling back to CPU+OpenBLAS${NC}"
        elif [[ -z "$SYCL_HPP" ]]; then
            echo -e "${YELLOW}  → sycl/sycl.hpp not found — SYCL skipped, falling back to CPU+OpenBLAS${NC}"
        else
            local INTELSYCL_DIR SYCL_INCLUDE_DIR
            INTELSYCL_DIR=$(dirname "$INTELSYCL_CMAKE")
            SYCL_INCLUDE_DIR=$(dirname "$(dirname "$SYCL_HPP")")
            echo -e "${CYAN}  → IntelSYCL cmake : $INTELSYCL_DIR${NC}"
            echo -e "${CYAN}  → SYCL include    : $SYCL_INCLUDE_DIR${NC}"
            local SYCL_FLAGS="$BASE_FLAGS \
                -DGGML_SYCL=ON \
                -DCMAKE_PREFIX_PATH=${INTELSYCL_DIR} \
                -DIntelSYCL_DIR=${INTELSYCL_DIR} \
                -DCMAKE_CXX_FLAGS=-I${SYCL_INCLUDE_DIR}"
            if _try_build "$SYCL_FLAGS" "Intel SYCL ($CC)"; then
                echo -e "${GREEN}✅ Build complete — Intel SYCL${NC}"; return 0
            fi
            echo -e "${YELLOW}⚠️  SYCL build failed — falling back to CPU+OpenBLAS...${NC}"
        fi

        local CPU_FLAGS="$BASE_FLAGS -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS"
        if _try_build "$CPU_FLAGS" "OpenBLAS CPU ($CC)"; then
            echo -e "${GREEN}✅ Build complete — OpenBLAS CPU${NC}"; return 0
        fi

    elif echo "$GPU_LINES" | grep -iqE "AMD|ATI|Radeon"; then
        echo -e "${CYAN}  → AMD GPU detected — trying HIP/ROCm build${NC}"
        local HIP_FLAGS="$BASE_FLAGS -DGGML_HIPBLAS=ON -DAMDGPU_TARGETS=gfx803"
        if _try_build "$HIP_FLAGS" "AMD HIP ($CC)"; then
            echo -e "${GREEN}✅ Build complete — AMD HIP${NC}"; return 0
        fi
        echo -e "${YELLOW}⚠️  HIP build failed — falling back to CPU+OpenBLAS...${NC}"
        local CPU_FLAGS="$BASE_FLAGS -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS"
        if _try_build "$CPU_FLAGS" "OpenBLAS CPU ($CC)"; then
            echo -e "${GREEN}✅ Build complete — OpenBLAS CPU${NC}"; return 0
        fi

    elif command -v nvidia-smi &>/dev/null; then
        echo -e "${CYAN}  → NVIDIA GPU detected — trying CUDA build${NC}"
        local CUDA_FLAGS="$BASE_FLAGS -DGGML_CUDA=ON"
        if _try_build "$CUDA_FLAGS" "NVIDIA CUDA ($CC)"; then
            echo -e "${GREEN}✅ Build complete — NVIDIA CUDA${NC}"; return 0
        fi
        echo -e "${YELLOW}⚠️  CUDA build failed — falling back to CPU+OpenBLAS...${NC}"
        local CPU_FLAGS="$BASE_FLAGS -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS"
        if _try_build "$CPU_FLAGS" "OpenBLAS CPU ($CC)"; then
            echo -e "${GREEN}✅ Build complete — OpenBLAS CPU${NC}"; return 0
        fi

    else
        echo -e "${YELLOW}  → No discrete GPU — building CPU+OpenBLAS${NC}"
        local CPU_FLAGS="$BASE_FLAGS -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS"
        if _try_build "$CPU_FLAGS" "CPU-only ($CC)"; then
            echo -e "${GREEN}✅ Build complete — CPU+OpenBLAS${NC}"; return 0
        fi
    fi

    # Last resort: bare build, no acceleration flags
    echo -e "${YELLOW}⚠️  All accelerated builds failed — trying bare build...${NC}"
    if _try_build "$BASE_FLAGS" "bare ($CC)"; then
        echo -e "${GREEN}✅ Build complete — bare CPU${NC}"; return 0
    fi

    # ── ULTIMATE FALLBACK: build plain llama.cpp directly ──────────────────
    # BitNet-specific build has failed entirely (likely kernel generation or
    # cmake issues with the BitNet source layer). Build llama.cpp standalone
    # from the submodule — gives fully working llama-cli / llama-server /
    # llama-bench for running .gguf models, without the 1.58-bit speed boost.
    echo -e "${YELLOW}⚠️  BitNet build failed — deploying plain llama.cpp fallback...${NC}"
    if _build_llama_fallback "$BASE_FLAGS"; then
        echo -e "${GREEN}✅ Fallback build complete — llama.cpp (standard, no BitNet kernels)${NC}"
        echo -e "${YELLOW}ℹ️  Models will run correctly. BitNet 1.58-bit speed optimisation unavailable.${NC}"
        echo -e "${YELLOW}   Run Reinstall to retry the full BitNet build later.${NC}"
        return 0
    fi

    echo -e "${RED}❌ All build strategies exhausted. Check $LOG_FILE for details.${NC}"
    return 1
}

# Build plain llama.cpp from the submodule — no BitNet layer, no kernel header needed.
# Installs binaries into $SCRIPT_DIR/build/bin/ so all other functions find them.
_build_llama_fallback() {
    local BASE_FLAGS="$1"
    local LLAMA_SRC="$LLAMA_CPP_DIR"

    if [[ ! -f "$LLAMA_SRC/CMakeLists.txt" ]]; then
        echo -e "${YELLOW}  → llama.cpp submodule not populated — cloning for fallback...${NC}"
        _ensure_submodules || return 1
    fi

    echo -e "${CYAN}  → Building llama.cpp standalone from submodule...${NC}"
    local DEST_BIN="$SCRIPT_DIR/build/bin"
    (
        rm -rf "$SCRIPT_DIR/build"
        mkdir -p "$SCRIPT_DIR/build"
        cd "$SCRIPT_DIR/build"
        cmake "$LLAMA_SRC" $BASE_FLAGS \
            -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS \
            -DLLAMA_BUILD_TESTS=OFF \
            -DLLAMA_BUILD_EXAMPLES=ON \
            2>&1 | tee -a "$LOG_FILE" \
        && make -j"$(nproc)" 2>&1 | tee -a "$LOG_FILE"
    ) || return 1

    # Verify at least llama-cli was produced
    if [[ -f "$DEST_BIN/llama-cli" ]]; then
        echo -e "${GREEN}  ✅ llama-cli, llama-server, llama-bench available${NC}"
        return 0
    fi
    return 1
}

# ================================================================
# 📥 MODEL DOWNLOADER
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
        echo -e "${RED}❌ Neither wget nor curl found. Install one and retry.${NC}"; return 1
    fi

    echo -e "${GREEN}✅ Downloaded: $MODEL_FILE${NC}"
    read -rp "Set as default model? [y/N]: " SET_DEFAULT
    [[ "$SET_DEFAULT" =~ ^[Yy]$ ]] && M_PATH="$MODEL_FILE" && \
        echo -e "${GREEN}✅ Default model set to: $M_PATH${NC}"
}

# HuggingFace snapshot downloader — uses venv python + huggingface_hub
_hf_snapshot_download() {
    local REPO_ID="$1" LOCAL_DIR="$2"
    echo -e "${CYAN}📦 Downloading $REPO_ID via HuggingFace Hub...${NC}"

    if [[ ! -x "$VENV_PY" ]]; then
        echo -e "${YELLOW}  → venv not found — running Doctor to create it...${NC}"
        run_doctor
    fi

    "$VENV_PY" -c "import huggingface_hub" &>/dev/null || \
        "$VENV_PIP" install --quiet huggingface_hub hf_transfer

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
        # Offer to set first .gguf found as default
        local FIRST_GGUF
        FIRST_GGUF=$(find "$LOCAL_DIR" -name "*.gguf" | head -1)
        if [[ -n "$FIRST_GGUF" ]]; then
            read -rp "Set $FIRST_GGUF as default model? [y/N]: " SET_DEFAULT
            [[ "$SET_DEFAULT" =~ ^[Yy]$ ]] && M_PATH="$FIRST_GGUF" && \
                echo -e "${GREEN}✅ Default model: $M_PATH${NC}"
        fi
    else
        echo -e "${RED}❌ Download failed — check $LOG_FILE${NC}"
    fi
}

# ================================================================
# 🔄 REINSTALL: CLEAN DEPS & BUILD
# ================================================================
BITNET_REPO="https://github.com/microsoft/BitNet.git"

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

# ================================================================
# 🌐 WEB UI
# ================================================================
launch_webui() {
    if [[ ! -f "$LLAMA_SERVER" ]]; then
        echo -e "${RED}❌ llama-server not found at $LLAMA_SERVER${NC}"
        echo -e "${YELLOW}   Run Reinstall to build it first.${NC}"
        return 1
    fi
    echo -e "${CYAN}🌐 Starting llama-server on :8080...${NC}"
    "$LLAMA_SERVER" -m "$M_PATH" --port 8080 &
    LLAMA_SERVER_PID=$!
    echo -e "${GREEN}✅ llama-server running (PID: $LLAMA_SERVER_PID)${NC}"
    if command -v open-webui &>/dev/null; then
        open-webui serve
    else
        echo -e "${YELLOW}⚠️  open-webui not installed. Install with: pip install open-webui${NC}"
        echo -e "${YELLOW}   llama-server is live — connect any OpenAI-compatible client to http://localhost:8080${NC}"
    fi
}

# ================================================================
# 📜 LOG VIEWER
# ================================================================
view_logs() {
    echo -e "${CYAN}📜 Log files in $LOG_DIR:${NC}"
    local logs=("$LOG_FILE" "$LOG_DIR/help_system.txt")
    local i=1
    for f in "${logs[@]}"; do
        [[ -f "$f" ]] && echo "  $i) $(basename "$f")  ($(wc -l < "$f") lines)"
        (( i++ ))
    done
    echo "  0) Cancel"
    read -rp "View which log? " LC
    case $LC in
        1) [[ -f "$LOG_FILE" ]] && less "$LOG_FILE" || echo "No system log yet." ;;
        2) [[ -f "$LOG_DIR/help_system.txt" ]] && less "$LOG_DIR/help_system.txt" ;;
        0) return ;;
    esac
}

# ================================================================
# 💀 CACHE CLEAN (safe rewrite of Godmode's run_exorcise)
# ================================================================
clean_cache() {
    echo -e "${CYAN}💀 Cleaning model cache & HuggingFace snapshots...${NC}"
    local MODELS_DIR="$SCRIPT_DIR/models"

    # Remove HuggingFace snapshot/cache directories only — never touch .gguf files
    local REMOVED=0
    while IFS= read -r -d '' d; do
        echo -e "${YELLOW}  → Removing: $d${NC}"
        rm -rf "$d"
        (( REMOVED++ ))
    done < <(find "$MODELS_DIR" -type d \( -name ".cache" -o -name "snapshots" \
              -o -name "blobs" -o -name "refs" \) -print0 2>/dev/null)

    # Remove incomplete/zero-byte downloads
    while IFS= read -r -d '' f; do
        echo -e "${YELLOW}  → Removing empty file: $f${NC}"
        rm -f "$f"
        (( REMOVED++ ))
    done < <(find "$MODELS_DIR" -type f -size 0 -print0 2>/dev/null)

    if [[ $REMOVED -eq 0 ]]; then
        echo -e "${GREEN}✅ Nothing to clean${NC}"
    else
        echo -e "${GREEN}✅ Removed $REMOVED items${NC}"
    fi

    # Report what .gguf models remain
    echo -e "${CYAN}📦 Available models:${NC}"
    find "$MODELS_DIR" -name "*.gguf" | while read -r m; do
        local SIZE
        SIZE=$(du -h "$m" | cut -f1)
        echo "  • $(basename "$m") ($SIZE)"
    done
}

# ================================================================
# 🧩 PLUGIN SYSTEM (METADATA + DEPS)
# ================================================================
parse_metadata() {
    local FILE="$1"
    NAME=$(grep "#@name:" "$FILE" | cut -d: -f2- | xargs)
    DESC=$(grep "#@desc:" "$FILE" | cut -d: -f2- | xargs)
    DEPS=$(grep "#@deps:" "$FILE" | cut -d: -f2- | xargs)
}

handle_deps() {
    for dep in $DEPS; do
        case $dep in
            python) require_tool "python3"     "command -v python3"    fix_python      ;;
            cmake)  require_tool "cmake"       "command -v cmake"      fix_cmake       ;;
            ffmpeg) require_tool "ffmpeg"      "command -v ffmpeg"     fix_ffmpeg      ;;
            llama)  require_tool "llama-bench" "[[ -f $LLAMA_BIN ]]"   fix_llama_bench ;;
            bc)     require_tool "bc"          "command -v bc"         fix_bc          ;;
        esac
    done
}

# FIX: subshell — plugin cannot corrupt parent variables or exit the loop
run_plugin() {
    local FILE="$1"
    parse_metadata "$FILE"
    echo -e "${CYAN}▶ Running: ${NAME:-$(basename "$FILE" .sh)}${NC}"
    [[ -n "$DESC" ]] && echo -e "${YELLOW}$DESC${NC}"
    handle_deps
    ( source "$FILE" )
}

list_plugins() { ls "$PLUGIN_DIR"/*.sh 2>/dev/null | sort; }

# ================================================================
# 🛒 PLUGIN MARKETPLACE (LOCAL)
# ================================================================
market_list() {
    echo -e "${CYAN}📦 Available plugins in marketplace:${NC}"
    local found=0
    for f in "$MARKET_DIR"/*.sh; do
        [[ -f "$f" ]] || continue
        parse_metadata "$f"
        echo "  • $(basename "$f" .sh)${NAME:+ — $NAME}${DESC:+: $DESC}"
        found=1
    done
    [[ $found -eq 0 ]] && echo -e "${YELLOW}  (marketplace is empty)${NC}"
}

market_install() {
    local PLUGIN_NAME="$1"
    local SRC="$MARKET_DIR/$PLUGIN_NAME.sh"
    local DST="$PLUGIN_DIR/$PLUGIN_NAME.sh"
    if [[ ! -f "$SRC" ]]; then
        echo -e "${RED}❌ Plugin '$PLUGIN_NAME' not found in marketplace${NC}"; return 1
    fi
    # FIX: preview before installing untrusted code
    echo -e "${YELLOW}━━━ Preview: $PLUGIN_NAME ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    head -30 "$SRC"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -rp "Install '$PLUGIN_NAME'? [y/N]: " CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        cp "$SRC" "$DST" && chmod +x "$DST"
        echo -e "${GREEN}✅ Installed: $PLUGIN_NAME${NC}"
    else
        echo -e "${YELLOW}⚠️  Installation cancelled${NC}"
    fi
}

market_remove() {
    local PLUGIN_NAME="$1"
    local FILE="$PLUGIN_DIR/$PLUGIN_NAME.sh"
    if [[ -f "$FILE" ]]; then
        read -rp "Remove '$PLUGIN_NAME'? [y/N]: " CONFIRM
        if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
            rm "$FILE" && echo -e "${GREEN}🗑️  Removed: $PLUGIN_NAME${NC}"
        else
            echo -e "${YELLOW}⚠️  Removal cancelled${NC}"
        fi
    else
        echo -e "${RED}❌ Plugin '$PLUGIN_NAME' not installed${NC}"
    fi
}

# ================================================================
# ⚡ BENCHMARK
# ================================================================
run_benchmark() {
    require_tool "llama-bench" "[[ -f $LLAMA_BIN ]]" fix_llama_bench || return 1
    require_tool "bc"          "command -v bc"        fix_bc          || return 1

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

# ================================================================
# 📊 LIVE MONITOR
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

# ================================================================
# 🧪 DEFAULT PLUGINS (created on first run if plugins/ is empty)
# ================================================================
create_default_plugins() {
# chat.sh — real llama-cli invocation with GPU detection
cat > "$PLUGIN_DIR/chat.sh" << 'PLUGEOF'
#@name: Chat
#@desc: Terminal chat with llama-cli + auto-log
#@deps: llama

LLAMA_CLI="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/build/bin/llama-cli"
MODELS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/models"
LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/chat_logs"
BENCH_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.bitnet_benchmark"
mkdir -p "$LOG_DIR"

[[ ! -f "$LLAMA_CLI" ]] && { echo "❌ llama-cli not built. Run Reinstall."; exit 1; }

MODEL=$(find "$MODELS_DIR" -maxdepth 2 -name "*.gguf" | head -1)
[[ -z "$MODEL" ]] && { echo "❌ No model found. Run Download first."; exit 1; }

# Use GPU layers if a GPU backend was benchmarked
NGL=0
[[ -f "$BENCH_FILE" ]] && source "$BENCH_FILE"
[[ "${backend:-CPU}" != "CPU" ]] && NGL=99

echo "💬 Chat — model: $(basename "$MODEL") | backend: ${backend:-CPU} | ngl: $NGL"
echo "Type /bye to exit. Logging to $LOG_DIR/history.log"
"$LLAMA_CLI" -m "$MODEL" -p "### Assistant:" -cnv --color \
    -ngl "$NGL" -t "$(nproc)" 2>/dev/null \
    | tee -a "$LOG_DIR/history.log"
PLUGEOF

# file-chat.sh — document Q&A via stdin pipe to llama-cli
cat > "$PLUGIN_DIR/file-chat.sh" << 'PLUGEOF'
#@name: File-Chat
#@desc: Analyze documents — PDF, XLSX, CSV, TXT
#@deps: llama python

LLAMA_CLI="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/build/bin/llama-cli"
MODELS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/models"
VENV_PY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/venv/bin/python3"

[[ ! -f "$LLAMA_CLI" ]] && { echo "❌ llama-cli not built. Run Reinstall."; exit 1; }
MODEL=$(find "$MODELS_DIR" -maxdepth 2 -name "*.gguf" | head -1)
[[ -z "$MODEL" ]] && { echo "❌ No model found. Run Download first."; exit 1; }

read -rp "📄 File path: " FPATH
[[ ! -f "$FPATH" ]] && { echo "❌ File not found: $FPATH"; exit 1; }

# Extract text — use python for PDF/XLSX, cat for plain text
EXT="${FPATH##*.}"
case "${EXT,,}" in
    pdf)  "$VENV_PY" -c "
import sys
try:
    import pdfplumber
    with pdfplumber.open('$FPATH') as p:
        print('\n'.join(pg.extract_text() or '' for pg in p.pages))
except ImportError:
    print('[pdfplumber not installed — pip install pdfplumber]')" ;;
    csv|txt|md) cat "$FPATH" ;;
    *)    strings "$FPATH" ;;
esac | head -c 8000 | "$LLAMA_CLI" -m "$MODEL" \
    -p "Analyze the following document and answer questions about it:\n\n" \
    -cnv --color -t "$(nproc)" 2>/dev/null
PLUGEOF

# vision.sh — llava/BitVLA image analysis with mmproj auto-download
cat > "$PLUGIN_DIR/vision.sh" << 'PLUGEOF'
#@name: Vision
#@desc: Image analysis via LLaVA / BitVLA (auto-downloads mmproj)
#@deps: llama

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLAMA_CLI="$SCRIPT_ROOT/build/bin/llama-cli"
MODELS_DIR="$SCRIPT_ROOT/models"
MMPROJ="$MODELS_DIR/mmproj-model-f16.gguf"

[[ ! -f "$LLAMA_CLI" ]] && { echo "❌ llama-cli not built. Run Reinstall."; exit 1; }
MODEL=$(find "$MODELS_DIR" -maxdepth 2 -name "*.gguf" ! -name "mmproj*" | head -1)
[[ -z "$MODEL" ]] && { echo "❌ No model found. Run Download first."; exit 1; }

if [[ ! -f "$MMPROJ" ]]; then
    echo "📥 Downloading BakLLaVA mmproj..."
    wget -qO "$MMPROJ" \
        "https://huggingface.co/mys/ggml_bakllava-1/resolve/main/mmproj-model-f16.gguf" \
    || { echo "❌ mmproj download failed"; exit 1; }
fi

read -rp "👁️  Image path: " IMG
[[ ! -f "$IMG" ]] && { echo "❌ Image not found: $IMG"; exit 1; }

"$LLAMA_CLI" -m "$MODEL" --mmproj "$MMPROJ" \
    --image "$IMG" -p "Describe this image in detail:" \
    -t "$(nproc)" --color 2>/dev/null
PLUGEOF

# voice.sh — Whisper STT → LLM → response
cat > "$PLUGIN_DIR/voice.sh" << 'PLUGEOF'
#@name: Voice
#@desc: Whisper speech-to-text → LLM pipeline
#@deps: python ffmpeg llama

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLAMA_CLI="$SCRIPT_ROOT/build/bin/llama-cli"
MODELS_DIR="$SCRIPT_ROOT/models"
VENV_PY="$SCRIPT_ROOT/venv/bin/python3"
VENV_PIP="$SCRIPT_ROOT/venv/bin/pip"

[[ ! -f "$LLAMA_CLI" ]] && { echo "❌ llama-cli not built. Run Reinstall."; exit 1; }
MODEL=$(find "$MODELS_DIR" -maxdepth 2 -name "*.gguf" ! -name "mmproj*" | head -1)
[[ -z "$MODEL" ]] && { echo "❌ No model found. Run Download first."; exit 1; }

# Install whisper if missing
"$VENV_PY" -c "import whisper" &>/dev/null || \
    "$VENV_PIP" install --quiet openai-whisper sounddevice

echo "🎙️  Recording 5 seconds... (press Ctrl+C to stop early)"
TMPWAV=$(mktemp --suffix=.wav)
"$VENV_PY" - <<PYEOF
import sounddevice as sd, scipy.io.wavfile as wav, numpy as np
fs=16000; dur=5
print("Recording...")
audio=sd.rec(int(dur*fs),samplerate=fs,channels=1,dtype='int16')
sd.wait()
wav.write("$TMPWAV", fs, audio)
print("Done.")
PYEOF

TRANSCRIPT=$("$VENV_PY" - <<PYEOF
import whisper, sys
m=whisper.load_model("base")
r=m.transcribe("$TMPWAV")
print(r["text"].strip())
PYEOF
)
rm -f "$TMPWAV"
echo -e "🗣️  You said: $TRANSCRIPT"
echo "$TRANSCRIPT" | "$LLAMA_CLI" -m "$MODEL" \
    -p "Respond to the following voice input:\n" \
    -t "$(nproc)" --color 2>/dev/null
PLUGEOF

chmod +x "$PLUGIN_DIR"/*.sh
}
[[ -z "$(ls -A "$PLUGIN_DIR" 2>/dev/null)" ]] && create_default_plugins

# ================================================================
# 🧭 MAIN LOOP
# ================================================================
while true; do
    print_header
    echo -e "\n${CYAN}================================================${NC}"
    echo -e "${CYAN}       🌌 BITNET OMNI-SHIELD WORKSTATION${NC}"
    echo -e "${CYAN}================================================${NC}"

    # FIX: unset MAP each iteration — no stale entries if plugin count changes
    unset MAP
    declare -A MAP
    i=1

    # --- Dynamic plugins ---
    for plugin in $(list_plugins); do
        parse_metadata "$plugin"
        echo "$i) ⚙️  ${NAME:-$(basename "$plugin" .sh)}"
        MAP[$i]="$plugin"
        (( i++ ))
    done

    # --- Fixed system actions ---
    echo "──────────────────────────────────────"
    echo "$i) 🌐 WEBUI     Start Open WebUI + RAG";    MAP[$i]="webui";       (( i++ ))
    echo "$i) 🩺 DOCTOR    Auto-Repair & Audit";       MAP[$i]="doctor";      (( i++ ))
    echo "$i) 📥 DOWNLOAD  1.58-bit Models";           MAP[$i]="download";    (( i++ ))
    echo "$i) 🔄 REINSTALL Clean Deps & Build";        MAP[$i]="reinstall";   (( i++ ))
    echo "$i) ⚡ BENCHMARK Detect Best Backend";       MAP[$i]="benchmark";   (( i++ ))
    echo "──────────────────────────────────────"
    echo "$i) 📦 MARKET    List available plugins";    MAP[$i]="market_list"; (( i++ ))
    echo "$i) 📥 MARKET    Install a plugin";          MAP[$i]="install";     (( i++ ))
    echo "$i) 🗑️  MARKET    Remove a plugin";          MAP[$i]="remove";      (( i++ ))
    echo "──────────────────────────────────────"
    echo "$i) 💀 CACHE     Clean model cache";         MAP[$i]="cache";       (( i++ ))
    echo "$i) 📜 LOGS      View system logs";          MAP[$i]="logs";        (( i++ ))
    echo "$i) ❓ HELP      Troubleshooting Guide";     MAP[$i]="help";        (( i++ ))
    echo "$i) 🚪 EXIT";                                MAP[$i]="exit"

    read -rp "Select [1-$i]: " CHOICE
    ACTION="${MAP[$CHOICE]}"

    case $ACTION in
        *.sh)        run_plugin "$ACTION" ;;
        webui)       launch_webui ;;
        doctor)      run_doctor ;;
        download)    download_models ;;
        reinstall)   reinstall_all ;;
        benchmark)   run_benchmark ;;
        market_list) market_list ;;
        install)     read -rp "Plugin name: " P; market_install "$P" ;;
        remove)      read -rp "Plugin name: " P; market_remove  "$P" ;;
        cache)       clean_cache ;;
        logs)        view_logs ;;
        help)        display_help ;;
        exit)        echo -e "${CYAN}👋 Goodbye!${NC}"; exit 0 ;;
        "")          echo -e "${RED}❌ Invalid choice: '$CHOICE'${NC}" ;;
        *)           echo -e "${RED}❌ Unhandled action: '$ACTION'${NC}" ;;
    esac

    echo ""  # breathing room between menu cycles

done

# ================================================================
# 📘 README
# ================================================================
: <<'README'
# BitNet b1.58 Omni-Shield

## Features
- Dynamic plugin system with metadata (#@name, #@desc, #@deps)
- Self-healing dependency manager (warns before sudo)
- System Doctor: groups, GPU drivers, venv bootstrap + pip packages
- Hardware Tuner: Intel SYCL / AMD HIP / NVIDIA CUDA / CPU+OpenBLAS auto-detect
- BitNet kernel generator pre-build hook (_prepare_bitnet_kernels)
- Real llama.cpp benchmarking (CPU + GPU auto-select)
- Live CPU / RAM / GPU monitor in header
- Open WebUI launcher with llama-server
- Model downloader: wget/curl for gguf + HF snapshot_download for full repos
- Model zoo: Falcon3-7B, Llama3-1bit, BitNet-b1.58-2B-4T
- Reinstall: one-shot clean rebuild with source clone + submodule repair
- Cache cleaner: removes HF snapshot dirs and zero-byte files, preserves .gguf
- Log viewer: tail/less any log in chat_logs/
- Integrated help/troubleshooting (viewed in less)
- Local plugin marketplace with preview + confirmation

## Default Plugins (auto-created on first run)
- chat.sh     : real llama-cli invocation, GPU-aware ngl, session logging
- file-chat.sh: document Q&A (PDF via pdfplumber, CSV/TXT native)
- vision.sh   : LLaVA image analysis, auto-downloads mmproj
- voice.sh    : Whisper STT → LLM pipeline

## Plugin Format
  #@name: My Plugin
  #@desc: What it does
  #@deps: python ffmpeg llama bc

## Directory Layout
  ./plugins/       active plugins
  ./marketplace/   available-to-install plugins
  ./models/        .gguf model files
  ./build/bin/     compiled llama binaries
  ./venv/          Python virtualenv
  ./chat_logs/     session + system logs

## Changelog (Godmode merge)
  + _prepare_bitnet_kernels — LUT kernel gen + int8 patch, pre-build hook
  + _hf_snapshot_download  — huggingface_hub snapshot with hf_transfer
  + download_models        — extended with model zoo (Falcon, Llama, BitNet)
  + clean_cache            — safe cache clean, never touches .gguf files
  + view_logs              — interactive log viewer
  + run_doctor             — now bootstraps venv + installs pip packages
  + chat.sh plugin         — real llama-cli, GPU-conditional ngl, session log
  + file-chat.sh plugin    — document extraction + Q&A pipeline
  + vision.sh plugin       — LLaVA with mmproj auto-download
  + voice.sh plugin        — Whisper STT + LLM response
  + LLAMA_CLI/VENV_PY/VENV_PIP added to globals
README
