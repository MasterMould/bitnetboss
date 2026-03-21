#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="bitnet-godmode"
echo "🚀 Creating Enterprise BitNet GODMODE Workstation..."

mkdir -p "$PROJECT"/{bin,core,system,models,runtime,config,logs,build,plugins}
cd "$PROJECT"
sudo apt install -y build-essential cmake clang libopenblas-dev libomp-dev

# --------------------------
# CONFIG
# --------------------------
cat > core/config.sh <<'EOF'
set -Eeuo pipefail
IFS=$'\n\t'

BITNET_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BITNET_DIR="$BITNET_ROOT/BitNet"
MODEL_DIR="$BITNET_ROOT/models"
LOG_DIR="$BITNET_ROOT/logs"
BUILD_DIR="$BITNET_ROOT/build"
VENV_DIR="$BITNET_ROOT/venv"

mkdir -p "$LOG_DIR" "$BUILD_DIR" "$MODEL_DIR"
LOG_FILE="$LOG_DIR/system.log"
EOF

# --------------------------
# LOGGING
# --------------------------
cat > core/logging.sh <<'EOF'
log_info()    { echo "[INFO]  $1" | tee -a "$LOG_FILE"; }
log_warn()    { echo "[WARN]  $1" | tee -a "$LOG_FILE"; }
log_error()   { echo "[ERROR] $1" | tee -a "$LOG_FILE" >&2; }
log_success() { echo "[OK]    $1" | tee -a "$LOG_FILE"; }
EOF

# --------------------------
# ERROR HANDLER
# --------------------------
cat > core/errors.sh <<'EOF'
error_handler() {
    echo "[FATAL] Error on line $1"
    exit 1
}
trap 'error_handler $LINENO' ERR
EOF

# --------------------------
# ENVIRONMENT SETUP
# --------------------------
cat > core/env.sh <<'EOF'
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

if [[ ! -d "$VENV_DIR" ]]; then
    python3 -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"
pip install --upgrade pip >/dev/null
pip install huggingface_hub >/dev/null
EOF

# --------------------------
# BUILD SYSTEM
# --------------------------
cat > system/build.sh <<'EOF'
source "$(dirname "${BASH_SOURCE[0]}")/../core/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../core/logging.sh"

sync_repo() {
    if [[ ! -d "$BITNET_DIR" ]]; then
        git clone --recursive https://github.com/microsoft/BitNet.git "$BITNET_DIR"
    fi
}

detect_gpu() {
    if command -v nvidia-smi >/dev/null 2>&1; then
        export GPU_FLAG="-DGGML_CUDA=ON"
        log_info "CUDA GPU detected"
    else
        export GPU_FLAG=""
        log_warn "No CUDA GPU detected"
    fi
}

build_bitnet() {
    sync_repo
    detect_gpu

    cd "$BITNET_DIR"
    git submodule update --init --recursive

    mkdir -p build && cd build
    cmake .. -DBITNET_OPTIMIZE=ON $GPU_FLAG
    make -j"$(nproc)"

    log_success "BitNet built successfully"
}
EOF

# --------------------------
# DOCTOR
# --------------------------
cat > system/doctor.sh <<'EOF'
source "$(dirname "${BASH_SOURCE[0]}")/../core/config.sh"

doctor() {
    echo "🩺 System Diagnostics"
    echo "RAM:"
    free -h
    echo "CPU:"
    lscpu | grep "Model name"
    echo "GPU:"
    command -v nvidia-smi && nvidia-smi || echo "No NVIDIA GPU"
}
EOF

# --------------------------
# MODEL ZOO
# --------------------------
cat > models/zoo.sh <<'EOF'
source "$(dirname "${BASH_SOURCE[0]}")/../core/config.sh"

download_model() {
    read -p "Enter HuggingFace repo ID: " R_ID
    TARGET="$MODEL_DIR/$(basename "$R_ID")"

    python3 - <<PY
from huggingface_hub import snapshot_download
snapshot_download(repo_id="$R_ID", local_dir="$TARGET", local_dir_use_symlinks=False)
PY

    echo "Model downloaded to $TARGET"
}
EOF

# --------------------------
# CHAT RUNTIME
# --------------------------
cat > runtime/chat.sh <<'EOF'
source "$(dirname "${BASH_SOURCE[0]}")/../core/config.sh"

chat() {
    MODELS=($(find "$MODEL_DIR" -type f -name "*.gguf"))

    if [[ ${#MODELS[@]} -eq 0 ]]; then
        echo "No models found."
        return
    fi

    for i in "${!MODELS[@]}"; do
        SIZE=$(du -h "${MODELS[$i]}" | cut -f1)
        echo "$i) $(basename "${MODELS[$i]}") [$SIZE]"
    done

    read -p "Select model index: " IDX
    [[ "$IDX" =~ ^[0-9]+$ ]] || { echo "Invalid"; return; }

    "$BITNET_DIR/build/bin/llama-cli" \
        -m "${MODELS[$IDX]}" \
        -p "You are a BitNet AI." \
        -cnv --color -ngl 99
}
EOF

# --------------------------
# MAIN LAUNCHER
# --------------------------
cat > bin/godmode <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$BASE_DIR/core/config.sh"
source "$BASE_DIR/core/logging.sh"
source "$BASE_DIR/core/errors.sh"
source "$BASE_DIR/core/env.sh"

source "$BASE_DIR/system/build.sh"
source "$BASE_DIR/system/doctor.sh"
source "$BASE_DIR/models/zoo.sh"
source "$BASE_DIR/runtime/chat.sh"

while true; do
    echo "🌌 BitNet GODMODE Workstation"
    echo "1) Build"
    echo "2) Download Model"
    echo "3) Chat"
    echo "4) Doctor"
    echo "5) Exit"
    read -p "Choice: " C

    case $C in
        1) build_bitnet ;;
        2) download_model ;;
        3) chat ;;
        4) doctor ;;
        5) exit 0 ;;
        *) echo "Invalid" ;;
    esac
done
EOF

chmod +x bin/godmode

echo "✅ Enterprise BitNet GODMODE scaffold created."
echo "➡ Enter directory and run: ./bin/godmode"

cd bitnet-godmode
./bin/godmode

