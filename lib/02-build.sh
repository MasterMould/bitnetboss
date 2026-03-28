#!/bin/bash
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && echo "Source this file, dont run it directly." && exit 1
# ================================================================
# 02-build.sh — Submodule management, kernel generation, hardware build
# Requires: 00-globals.sh, 01-deps.sh
# ================================================================

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
        echo -e "${YELLOW}  → Generator not found — using synthesiser${NC}"
        _synthesise_lut_header "$HEADER" || return 1
        # Apply patch then return — no generator to run
        local PATCH_TARGET="$SCRIPT_DIR/src/ggml-bitnet-mad.cpp"
        if [[ -f "$PATCH_TARGET" ]] && grep -q "int8_t \* y_col" "$PATCH_TARGET"; then
            sed -i 's/int8_t \* y_col/const int8_t \* y_col/g' "$PATCH_TARGET"
        fi
        return 0
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
# ================================================================
# ⚙️ HARDWARE DETECTION & UNSTOPPABLE DRIVER VALIDATION
# ================================================================
_detect_and_prep_gpu() {
    echo -e "\n${CYAN}🔍 Executing high-precision hardware detection...${NC}"
    
    # 1. Isolate discrete vs integrated GPUs using vendor strings
    local PCI_VGA
    PCI_VGA=$(lspci | grep -iE "VGA|3D controller")
    
    HAS_NVIDIA=$(echo "$PCI_VGA" | grep -ic "NVIDIA")
    HAS_AMD=$(echo "$PCI_VGA" | grep -ic "AMD\|Radeon")
    HAS_INTEL_ARC=$(echo "$PCI_VGA" | grep -ic "Arc")
    HAS_INTEL_IGPU=$(echo "$PCI_VGA" | grep -ic "Intel") # If Arc is 0 but this is >0, it's an iGPU

    # 2. NVIDIA Validation & Auto-Install
    if [[ "$HAS_NVIDIA" -gt 0 ]]; then
        echo -e "${CYAN}  → NVIDIA hardware detected.${NC}"
        if ! command -v nvcc &>/dev/null; then
            echo -e "${YELLOW}  → Missing CUDA Toolkit. Initiating automatic aggressive install...${NC}"
            export DEBIAN_FRONTEND=noninteractive
            sudo apt-get update -qq
            sudo apt-get install -y nvidia-cuda-toolkit || echo -e "${RED}⚠️ CUDA install failed, continuing anyway...${NC}"
        fi
        TARGET_GPU="NVIDIA"
        return 0
    fi

    # 3. AMD Validation & Auto-Install
    if [[ "$HAS_AMD" -gt 0 ]]; then
        echo -e "${CYAN}  → AMD/Radeon hardware detected.${NC}"
        if ! command -v hipcc &>/dev/null; then
            echo -e "${YELLOW}  → Missing HIP/ROCm tools. Initiating automatic aggressive install...${NC}"
            export DEBIAN_FRONTEND=noninteractive
            sudo apt-get update -qq
            sudo apt-get install -y rocm-dev || echo -e "${RED}⚠️ ROCm install failed. AMD builds may fallback.${NC}"
        fi
        TARGET_GPU="AMD"
        return 0
    fi

    # 4. Intel Arc (Discrete) Validation & Auto-Install
    if [[ "$HAS_INTEL_ARC" -gt 0 ]]; then
        echo -e "${CYAN}  → Intel Arc (Discrete GPU) detected.${NC}"
        TARGET_GPU="INTEL_ARC"
        return 0
    fi

    # 5. Intel iGPU or Pure CPU
    if [[ "$HAS_INTEL_IGPU" -gt 0 && "$HAS_INTEL_ARC" -eq 0 ]]; then
        echo -e "${CYAN}  → Intel Integrated Graphics detected. Treating as CPU for stability.${NC}"
    else
        echo -e "${CYAN}  → No discrete GPU detected. Optimizing for CPU.${NC}"
    fi
    TARGET_GPU="CPU"
    return 0
}

# ================================================================
# 🚀 UNSTOPPABLE BUILD WATERFALL
# ================================================================
configure_hardware() {
    _detect_and_prep_gpu
    
    # Define our compiler arsenal (Most preferred to least)
    local COMPILERS=("clang-18" "clang" "gcc")
    local VALID_COMPILERS=()
    
    for c in "${COMPILERS[@]}"; do
        if command -v "$c" &>/dev/null; then
            VALID_COMPILERS+=("$c")
        fi
    done

    # Auto-install clang-18 if we have absolutely nothing
    if [[ ${#VALID_COMPILERS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}  → No valid compilers found. Forcing clang-18 installation...${NC}"
        sudo apt-get update -qq && sudo apt-get install -y clang-18 llvm-18-dev libomp-18-dev
        VALID_COMPILERS=("clang-18" "gcc")
    fi

    # Find OpenMP (required for BitNet CPU threading)
    if ! find /usr/lib -name "libomp.so" 2>/dev/null | grep -q .; then
        sudo apt-get install -y libomp-dev >>"$LOG_FILE" 2>&1
    fi
    local OMP_LIB=$(find /usr/lib/llvm-* /usr/lib/x86_64-linux-gnu /usr/lib -name "libomp.so" 2>/dev/null | head -1)
    local OPENMP_FLAGS=""
    if [[ -n "$OMP_LIB" ]]; then
        OPENMP_FLAGS="-DOpenMP_C_FLAGS=-fopenmp -DOpenMP_CXX_FLAGS=-fopenmp -DOpenMP_C_LIB_NAMES=omp -DOpenMP_CXX_LIB_NAMES=omp -DOpenMP_omp_LIBRARY=${OMP_LIB}"
    fi

    # ---------------------------------------------------------
    # STAGE 1: TARGETED GPU BUILDS
    # We loop through available compilers to force a success
    # ---------------------------------------------------------
    for CC in "${VALID_COMPILERS[@]}"; do
        local CXX="${CC/clang/clang++}"
        CXX="${CXX/gcc/g++}"
        local BASE_FLAGS="-DCMAKE_C_COMPILER=$CC -DCMAKE_CXX_COMPILER=$CXX $OPENMP_FLAGS"

        if [[ "$TARGET_GPU" == "NVIDIA" ]]; then
            echo -e "${CYAN}  → Attempting NVIDIA CUDA build with $CC...${NC}"
            if _try_build "$BASE_FLAGS -DGGML_CUDA=ON" "NVIDIA CUDA ($CC)"; then
                echo -e "${GREEN}✅ Build complete — NVIDIA CUDA${NC}"; return 0
            fi
        fi

        if [[ "$TARGET_GPU" == "AMD" ]]; then
            echo -e "${CYAN}  → Attempting AMD HIP build with $CC...${NC}"
            # Let CMake detect AMDGPU_TARGETS automatically first, it's safer than hardcoding gfx803
            if _try_build "$BASE_FLAGS -DGGML_HIPBLAS=ON" "AMD HIP ($CC)"; then
                echo -e "${GREEN}✅ Build complete — AMD HIP${NC}"; return 0
            fi
        fi

        if [[ "$TARGET_GPU" == "INTEL_ARC" ]]; then
            echo -e "${CYAN}  → Attempting Intel SYCL build with $CC...${NC}"
            local ONEAPI_ROOT="/opt/intel/oneapi"
            [[ -f "$ONEAPI_ROOT/setvars.sh" ]] && source "$ONEAPI_ROOT/setvars.sh" --force 2>/dev/null
            local INTELSYCL_CMAKE=$(find "$ONEAPI_ROOT" -name "IntelSYCLConfig.cmake" 2>/dev/null | head -1)
            if [[ -n "$INTELSYCL_CMAKE" ]]; then
                local INTELSYCL_DIR=$(dirname "$INTELSYCL_CMAKE")
                if _try_build "$BASE_FLAGS -DGGML_SYCL=ON -DCMAKE_PREFIX_PATH=${INTELSYCL_DIR}" "Intel SYCL ($CC)"; then
                    echo -e "${GREEN}✅ Build complete — Intel SYCL${NC}"; return 0
                fi
            fi
        fi
    done

    # ---------------------------------------------------------
    # STAGE 2: BITNET CPU WATERFALL (Try Much Harder)
    # If GPUs failed or aren't present, aggressively optimize for CPU
    # ---------------------------------------------------------
    echo -e "${YELLOW}⚠️ GPU build bypassed or failed. Engaging aggressive BitNet CPU fallback...${NC}"
    
    # Check CPU capabilities
    local CPU_INFO=$(lscpu)
    local HAS_AVX512=$(echo "$CPU_INFO" | grep -io "avx512")
    local HAS_AVX2=$(echo "$CPU_INFO" | grep -io "avx2")

    for CC in "${VALID_COMPILERS[@]}"; do
        local CXX="${CC/clang/clang++}"
        CXX="${CXX/gcc/g++}"
        local BASE_FLAGS="-DCMAKE_C_COMPILER=$CC -DCMAKE_CXX_COMPILER=$CXX $OPENMP_FLAGS"

        # Try AVX-512 first if hardware supports it
        if [[ -n "$HAS_AVX512" ]]; then
            echo -e "${CYAN}  → Attempting BitNet CPU build with AVX-512 ($CC)...${NC}"
            if _try_build "$BASE_FLAGS -DGGML_AVX512=ON -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS" "AVX-512 CPU ($CC)"; then
                echo -e "${GREEN}✅ Build complete — CPU AVX-512 + OpenBLAS${NC}"; return 0
            fi
        fi

        # Try AVX2
        if [[ -n "$HAS_AVX2" ]]; then
            echo -e "${CYAN}  → Attempting BitNet CPU build with AVX2 ($CC)...${NC}"
            if _try_build "$BASE_FLAGS -DGGML_AVX2=ON -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS" "AVX2 CPU ($CC)"; then
                echo -e "${GREEN}✅ Build complete — CPU AVX2 + OpenBLAS${NC}"; return 0
            fi
        fi

        # Try generic OpenBLAS
        echo -e "${CYAN}  → Attempting generic BitNet CPU build with OpenBLAS ($CC)...${NC}"
        if _try_build "$BASE_FLAGS -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS" "OpenBLAS CPU ($CC)"; then
            echo -e "${GREEN}✅ Build complete — CPU OpenBLAS${NC}"; return 0
        fi
        
        # Try barebones BitNet
        if _try_build "$BASE_FLAGS" "Bare BitNet CPU ($CC)"; then
            echo -e "${GREEN}✅ Build complete — CPU Barebones${NC}"; return 0
        fi
    done

    # ---------------------------------------------------------
    # STAGE 3: TOTAL DEFEAT FALLBACK
    # ---------------------------------------------------------
    echo -e "${RED}❌ All BitNet kernel strategies exhausted. Falling back to plain llama.cpp...${NC}"
    # Pick the best compiler we found earlier
    local FALLBACK_CC="${VALID_COMPILERS[0]}"
    local FALLBACK_CXX="${FALLBACK_CC/clang/clang++}"
    FALLBACK_CXX="${FALLBACK_CXX/gcc/g++}"
    
    if _build_llama_fallback "-DCMAKE_C_COMPILER=$FALLBACK_CC -DCMAKE_CXX_COMPILER=$FALLBACK_CXX"; then
        echo -e "${GREEN}✅ Fallback build complete — plain llama.cpp${NC}"
        return 0
    fi

    echo -e "${RED}❌ Unstoppable methodology reached a fatal stop. Check $LOG_FILE.${NC}"
    return 1
}
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
