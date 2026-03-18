#!/bin/bash
# =================================================================
# 🛡️ BITNET b1.58 OMNI-GPU: INTEL ARC A770 + AMD + NVIDIA (2026)
# =================================================================
set -e

# --- 1. SYSTEM HARDENING & FULL REQUIREMENT INSTALLATION ---
echo "🏗️  Installing All 2026 Requirements (Text/Voice/Vision/GPU)..."

# Add Intel oneAPI Repository for Arc A770 Support
if ! command -v icpx &> /dev/null; then
    wget -O- https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB | sudo gpg --dearmor -o /usr/share/keyrings/oneapi-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" | sudo tee /etc/apt/sources.list.d/oneAPI.list
fi

sudo apt update && sudo apt install -y \
    git cmake build-essential clang-18 llvm-18 curl pandoc ffmpeg \
    poppler-utils libmagic1 portaudio19-dev libasound2-dev espeak-ng \
    opencv-data libopencv-dev libnuma-dev \
    intel-oneapi-compiler-dpcpp-cpp intel-oneapi-mkl intel-oneapi-level-zero

export CC=clang-18
export CXX=clang++-18

# --- 2. ENVIRONMENT & DIRECTORY SETUP ---
[[ ! -d "BitNet" ]] && git clone --recursive https://github.com/microsoft/BitNet.git
cd BitNet
mkdir -p chat_logs models personas

[[ ! -d "venv" ]] && python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt huggingface_hub openai open-webui \
    pypdf python-docx pandas openpyxl openai-whisper piper-tts \
    pillow opencv-python transformers 

# --- 3. HARDWARE AUTO-TUNER (Intel Arc A770 / AMD / NVIDIA) ---
configure_hardware() {
    echo -e "\n🔍 Detecting GPU Architecture..."
    FLAGS="-DBITNET_OPTIMIZE=ON"
    
    # Check for Intel Arc (SYCL)
    if lspci | grep -i "VGA" | grep -iq "Intel"; then
        echo "🚀 Intel GPU Detected (Arc A770). Enabling SYCL/oneAPI..."
        source /opt/intel/oneapi/setvars.sh || true
        FLAGS="$FLAGS -DGGML_SYCL=ON -DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx"
    # Check for AMD (ROCm/HIP)
    elif lspci | grep -i "VGA" | grep -iq "AMD"; then
        echo "🚀 AMD GPU Detected. Enabling ROCm/HIP (gfx803+)..."
        FLAGS="$FLAGS -DGGML_HIPBLAS=ON -DAMDGPU_TARGETS=gfx803,gfx1030,gfx1100" 
    # Check for NVIDIA (CUDA)
    elif nvidia-smi &>/dev/null; then
        echo "🚀 NVIDIA GPU Detected. Enabling CUDA..."
        FLAGS="$FLAGS -DGGML_CUDA=ON"
    fi

    # CPU AVX-512 Fallback/Parallelism
    [[ $(grep -o "avx512" /proc/cpuinfo) ]] && FLAGS="$FLAGS -DGGML_AVX512=ON"

    mkdir -p build && cd build
    cmake .. $FLAGS
    make -j$(nproc)
    cd ..
}
[[ ! -d "build" ]] && configure_hardware

# --- 4. AUTO-LOGGING SYSTEM (Retained) ---
log_session() {
    local type=$1
    local content=$2
    local timestamp=$(date "+%Y-%m-%d_%H-%M-%S")
    echo -e "--- SESSION: $timestamp ---\nTYPE: $type\n\n$content\n\n" >> "chat_logs/history.log"
}

# --- 5. PERSONA LIBRARY (Retained) ---
select_persona() {
    echo -e "\n🎭 SELECT AN AI PERSONA:"
    echo "1) Standard  2) Coder  3) Data Analyst  4) Teacher  5) Pirate  6) Custom"
    read -p "Selection [1-6]: " P_C
    case $P_C in
        2) PERS="Expert Coder";; 3) PERS="Data Analyst";; 4) PERS="Socratic Teacher";;
        5) PERS="Grumpy Pirate";; 6) read -p "Prompt: " PERS;; *) PERS="Assistant";;
    esac
}

# --- 6. THE COMMAND CENTER ---
while true; do
    echo -e "\n================================================"
    echo "       🌌 BITNET UNIVERSAL WORKSTATION (v2026.7)"
    echo "================================================"
    echo "1) 💬 CHAT: Terminal + Persona + Auto-Log"
    echo "2) 📄 FILE-CHAT: Analyze Docs (PDF/XLSX/CSV)"
    echo "3) 👁️  VISION: BitVLA Image Analysis"
    echo "4) 🎙️ VOICE: Whisper + Piper Pipeline"
    echo "5) 🎨 WEBUI: Start Open WebUI + RAG"
    echo "6) 🛠️  DEV: Benchmarking / Conversion"
    echo "7) 📥 DOWNLOAD: 1.58-bit Models"
    echo "8) 🔄 UPDATE: Pull Source & Rebuild"
    echo "9) 🚪 EXIT"
    read -p "Selection [1-9]: " CHOICE

    case $CHOICE in
        1|2|3|4)
            MODELS=($(find models -maxdepth 2 -name "*.gguf" 2>/dev/null))
            [[ ${#MODELS[@]} -eq 0 ]] && { echo "❌ No models found."; continue; }
            echo -e "\n📂 Models:"; for i in "${!MODELS[@]}"; do echo "$((i+1))) ${MODELS[$i]}"; done
            read -p "Choice: " M_NUM; M_PATH="${MODELS[$((M_NUM-1))]}"
            read -p "🧵 Threads [$(nproc)]: " THRD; THRD=${THRD:-$(nproc)}

            if [[ "$CHOICE" == "1" ]]; then
                select_persona
                ./build/bin/llama-cli -m "$M_PATH" -p "System: $PERS \nUser: " -t "$THRD" -cnv | tee -a .temp_chat
                log_session "CHAT" "$(cat .temp_chat)" && rm .temp_chat
            elif [[ "$CHOICE" == "2" ]]; then
                read -p "📎 File Path: " F_P
                TEXT=$(python3 -c "import pypdf, docx, pandas as pd; p='$F_P'
try:
    if p.endswith('.pdf'): print(' '.join([pg.extract_text() for pg in pypdf.PdfReader(p).pages]))
    elif p.endswith('.docx'): print('\n'.join([pa.text for pa in docx.Document(p).paragraphs]))
    elif p.endswith(('.csv','.xlsx')): print(pd.read_excel(p).to_string() if p.endswith('.xlsx') else pd.read_csv(p).to_string())
    else: print(open(p,'r').read())
except: print('Error')")
                ./build/bin/llama-cli -m "$M_PATH" -p "Context: $TEXT \nUser: " -t "$THRD" -cnv | tee -a .temp_file
                log_session "FILE ($F_P)" "$(cat .temp_file)" && rm .temp_file
            elif [[ "$CHOICE" == "3" ]]; then
                read -p "🖼️ Image: " IMG_P; python3 utils/vision_handler.py --image "$IMG_P" --model "$M_PATH"
            elif [[ "$CHOICE" == "4" ]]; then
                python3 utils/voice_pipeline.py --model "$M_PATH" --threads "$THRD"
            fi
            ;;
        5) ./build/bin/llama-server -m "$M_PATH" --port 8080 -t "$THRD" &
           PID=$! && export OPENAI_API_BASE_URL="http://127.0.0.1:8080/v1" && open-webui serve && kill $PID ;;
        6) ./build/bin/llama-bench -m "$M_PATH" -t "$THRD" ;;
        7) echo "1) 0.7B 2) 2B 3) 3B 4) BitVLA"; read -p "C: " D_C
           [[ "$D_C" == "1" ]] && M_ID="microsoft/bitnet_b1_58-large"
           [[ "$D_C" == "2" ]] && M_ID="microsoft/bitnet-b1.58-2B-4T"
           [[ "$D_C" == "3" ]] && M_ID="microsoft/bitnet_b1_58-3B"
           [[ "$D_C" == "4" ]] && M_ID="lxsy/bitvla-bf16"
           python3 utils/download-model.py --model "$M_ID" --local-dir "models/${M_ID##*/}" ;;
        8) git pull --recursive && configure_hardware ;;
        9) exit 0 ;;
    esac
done
