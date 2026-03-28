#!/bin/bash
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && echo "Source this file, dont run it directly." && exit 1
# ================================================================
# 07-plugins.sh — Plugin system, metadata, deps, default plugins
# Requires: 00-globals.sh, 01-deps.sh, 02-build.sh
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

create_default_plugins() {
cat > "$PLUGIN_DIR/chat.sh" << 'PLUGEOF'
#@name: Chat
#@desc: Terminal chat with llama-cli + auto-log
#@deps: llama

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLAMA_CLI="$SCRIPT_ROOT/build/bin/llama-cli"
MODELS_DIR="$SCRIPT_ROOT/models"
LOG_DIR="$SCRIPT_ROOT/chat_logs"
BENCH_FILE="$SCRIPT_ROOT/.bitnet_benchmark"
mkdir -p "$LOG_DIR"

# Auto-build if binary missing
if [[ ! -f "$LLAMA_CLI" ]]; then
    echo "🔨 Building llama-cli..."
    bash "$SCRIPT_ROOT/$(basename "${BASH_SOURCE[1]}")" --build-only 2>/dev/null \
        || (cd "$SCRIPT_ROOT" && source "$(basename "${BASH_SOURCE[1]}")" configure_hardware 2>/dev/null)
    # Final check — use configure_hardware from parent if still missing
    [[ ! -f "$LLAMA_CLI" ]] && { echo "❌ Build failed — run Reinstall from the main menu"; exit 1; }
fi

# Auto-find or wait for model
MODEL=$(find "$MODELS_DIR" -maxdepth 2 -name "*.gguf" 2>/dev/null | head -1)
if [[ -z "$MODEL" ]]; then
    echo "📥 No model found — downloading BitNet-b1.58-2B-4T..."
    mkdir -p "$MODELS_DIR"
    wget -c --show-progress \
        -O "$MODELS_DIR/bitnet-b1.58-2B-4T.gguf" \
        "https://huggingface.co/microsoft/BitNet-b1.58-2B-4T-gguf/resolve/main/ggml-model-i2_s.gguf" \
    || curl -L --progress-bar \
        -o "$MODELS_DIR/bitnet-b1.58-2B-4T.gguf" \
        "https://huggingface.co/microsoft/BitNet-b1.58-2B-4T-gguf/resolve/main/ggml-model-i2_s.gguf"
    MODEL=$(find "$MODELS_DIR" -maxdepth 2 -name "*.gguf" 2>/dev/null | head -1)
    [[ -z "$MODEL" ]] && { echo "❌ Download failed — check internet connection"; exit 1; }
fi

NGL=0
[[ -f "$BENCH_FILE" ]] && source "$BENCH_FILE"
[[ "${backend:-CPU}" != "CPU" ]] && NGL=99

echo "💬 Chat — model: $(basename "$MODEL") | backend: ${backend:-CPU} | ngl: $NGL"
echo "Type /bye to exit. Logging to $LOG_DIR/history.log"
"$LLAMA_CLI" -m "$MODEL" -p "### Assistant:" -cnv --color \
    -ngl "$NGL" -t "$(nproc)" 2>/dev/null \
    | tee -a "$LOG_DIR/history.log"
PLUGEOF

cat > "$PLUGIN_DIR/file-chat.sh" << 'PLUGEOF'
#@name: File-Chat
#@desc: Analyze documents — PDF, XLSX, CSV, TXT
#@deps: llama python

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLAMA_CLI="$SCRIPT_ROOT/build/bin/llama-cli"
MODELS_DIR="$SCRIPT_ROOT/models"
VENV_PY="$SCRIPT_ROOT/venv/bin/python3"
VENV_PIP="$SCRIPT_ROOT/venv/bin/pip"

# Auto-build if binary missing
if [[ ! -f "$LLAMA_CLI" ]]; then
    echo "🔨 Building llama-cli..."
    configure_hardware 2>/dev/null || true
    [[ ! -f "$LLAMA_CLI" ]] && { echo "❌ Build failed — run Reinstall from main menu"; exit 1; }
fi

# Auto-download if no model
MODEL=$(find "$MODELS_DIR" -maxdepth 2 -name "*.gguf" 2>/dev/null | head -1)
if [[ -z "$MODEL" ]]; then
    echo "📥 Downloading model..."
    mkdir -p "$MODELS_DIR"
    wget -qO "$MODELS_DIR/bitnet-b1.58-2B-4T.gguf" \
        "https://huggingface.co/microsoft/BitNet-b1.58-2B-4T-gguf/resolve/main/ggml-model-i2_s.gguf" \
    || curl -sSL -o "$MODELS_DIR/bitnet-b1.58-2B-4T.gguf" \
        "https://huggingface.co/microsoft/BitNet-b1.58-2B-4T-gguf/resolve/main/ggml-model-i2_s.gguf" \
    || true
    MODEL=$(find "$MODELS_DIR" -maxdepth 2 -name "*.gguf" 2>/dev/null | head -1)
    [[ -z "$MODEL" ]] && { echo "❌ Download failed — check internet connection"; exit 1; }
fi

read -rp "📄 File path: " FPATH
[[ ! -f "$FPATH" ]] && { echo "❌ File not found: $FPATH"; exit 1; }

EXT="${FPATH##*.}"
case "${EXT,,}" in
    pdf)
        "$VENV_PY" -c "import pdfplumber" &>/dev/null || \
            "$VENV_PIP" install --quiet pdfplumber >/dev/null 2>&1
        "$VENV_PY" -c "
import pdfplumber, sys
try:
    with pdfplumber.open('$FPATH') as p:
        print('\n'.join(pg.extract_text() or '' for pg in p.pages))
except Exception as e:
    print(f'PDF error: {e}', file=sys.stderr)" ;;
    csv|txt|md) cat "$FPATH" ;;
    *) strings "$FPATH" ;;
esac | head -c 8000 | "$LLAMA_CLI" -m "$MODEL" \
    -p "Analyze the following document and answer questions about it:\n\n" \
    -cnv --color -t "$(nproc)" 2>/dev/null
PLUGEOF

cat > "$PLUGIN_DIR/vision.sh" << 'PLUGEOF'
#@name: Vision
#@desc: Image analysis via LLaVA / BitVLA (auto-downloads mmproj)
#@deps: llama

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLAMA_CLI="$SCRIPT_ROOT/build/bin/llama-cli"
MODELS_DIR="$SCRIPT_ROOT/models"
MMPROJ="$MODELS_DIR/mmproj-model-f16.gguf"

# Auto-build if binary missing
if [[ ! -f "$LLAMA_CLI" ]]; then
    echo "🔨 Building llama-cli..."
    configure_hardware 2>/dev/null || true
    [[ ! -f "$LLAMA_CLI" ]] && { echo "❌ Build failed — run Reinstall from main menu"; exit 1; }
fi

# Auto-download model if missing
MODEL=$(find "$MODELS_DIR" -maxdepth 2 -name "*.gguf" ! -name "mmproj*" 2>/dev/null | head -1)
if [[ -z "$MODEL" ]]; then
    echo "📥 Downloading model..."
    mkdir -p "$MODELS_DIR"
    wget -qO "$MODELS_DIR/bitnet-b1.58-2B-4T.gguf" \
        "https://huggingface.co/microsoft/BitNet-b1.58-2B-4T-gguf/resolve/main/ggml-model-i2_s.gguf" \
    || curl -sSL -o "$MODELS_DIR/bitnet-b1.58-2B-4T.gguf" \
        "https://huggingface.co/microsoft/BitNet-b1.58-2B-4T-gguf/resolve/main/ggml-model-i2_s.gguf" \
    || true
    MODEL=$(find "$MODELS_DIR" -maxdepth 2 -name "*.gguf" ! -name "mmproj*" 2>/dev/null | head -1)
    [[ -z "$MODEL" ]] && { echo "❌ Download failed — check internet connection"; exit 1; }
fi

# Auto-download mmproj — try wget then curl
if [[ ! -s "$MMPROJ" ]]; then
    echo "📥 Downloading mmproj..."
    MMPROJ_URL="https://huggingface.co/mys/ggml_bakllava-1/resolve/main/mmproj-model-f16.gguf"
    wget -qO "$MMPROJ" "$MMPROJ_URL" 2>/dev/null || rm -f "$MMPROJ"
    [[ ! -s "$MMPROJ" ]] && \
        curl -sSL -o "$MMPROJ" "$MMPROJ_URL" 2>/dev/null || rm -f "$MMPROJ"
    [[ ! -s "$MMPROJ" ]] && { echo "❌ mmproj download failed — check internet"; exit 1; }
fi

read -rp "👁️  Image path: " IMG
[[ ! -f "$IMG" ]] && { echo "❌ Image not found: $IMG"; exit 1; }

"$LLAMA_CLI" -m "$MODEL" --mmproj "$MMPROJ" \
    --image "$IMG" -p "Describe this image in detail:" \
    -t "$(nproc)" --color 2>/dev/null
PLUGEOF

cat > "$PLUGIN_DIR/voice.sh" << 'PLUGEOF'
#@name: Voice
#@desc: Whisper speech-to-text → LLM pipeline
#@deps: python ffmpeg llama

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLAMA_CLI="$SCRIPT_ROOT/build/bin/llama-cli"
MODELS_DIR="$SCRIPT_ROOT/models"
VENV_PY="$SCRIPT_ROOT/venv/bin/python3"
VENV_PIP="$SCRIPT_ROOT/venv/bin/pip"

# Auto-build if binary missing
if [[ ! -f "$LLAMA_CLI" ]]; then
    echo "🔨 Building llama-cli..."
    configure_hardware 2>/dev/null || true
    [[ ! -f "$LLAMA_CLI" ]] && { echo "❌ Build failed — run Reinstall from main menu"; exit 1; }
fi

# Auto-download model if missing
MODEL=$(find "$MODELS_DIR" -maxdepth 2 -name "*.gguf" ! -name "mmproj*" 2>/dev/null | head -1)
if [[ -z "$MODEL" ]]; then
    echo "📥 Downloading model..."
    mkdir -p "$MODELS_DIR"
    wget -qO "$MODELS_DIR/bitnet-b1.58-2B-4T.gguf" \
        "https://huggingface.co/microsoft/BitNet-b1.58-2B-4T-gguf/resolve/main/ggml-model-i2_s.gguf" \
    || curl -sSL -o "$MODELS_DIR/bitnet-b1.58-2B-4T.gguf" \
        "https://huggingface.co/microsoft/BitNet-b1.58-2B-4T-gguf/resolve/main/ggml-model-i2_s.gguf" \
    || true
    MODEL=$(find "$MODELS_DIR" -maxdepth 2 -name "*.gguf" ! -name "mmproj*" 2>/dev/null | head -1)
    [[ -z "$MODEL" ]] && { echo "❌ Download failed — check internet connection"; exit 1; }
fi

# Auto-install whisper + sounddevice if missing
"$VENV_PY" -c "import whisper" &>/dev/null || \
    "$VENV_PIP" install --quiet openai-whisper sounddevice scipy >/dev/null 2>&1

echo "🎙️  Recording 5 seconds..."
TMPWAV=$(mktemp --suffix=.wav)
"$VENV_PY" - <<PYEOF
import sounddevice as sd, scipy.io.wavfile as wav
fs=16000; dur=5
audio=sd.rec(int(dur*fs),samplerate=fs,channels=1,dtype='int16')
sd.wait()
wav.write("$TMPWAV", fs, audio)
PYEOF

TRANSCRIPT=$("$VENV_PY" - <<PYEOF
import whisper
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

    # Guard: dir must exist before chmod
    mkdir -p "$PLUGIN_DIR"
    chmod +x "$PLUGIN_DIR"/*.sh 2>/dev/null || true
}
# Note: create_default_plugins is called by omni-shield.sh after mkdir -p,
# not here at source time when the directory may not yet exist.

