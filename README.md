

Simple local AI for Ubuntu 24.04  

  
================================================  
       🌌 BITNET OMNI-SHIELD WORKSTATION  
================================================  
1) ⚙️  Chat
2) ⚙️  File-Chat
3) ⚙️  Vision
4) ⚙️  Voice  
──────────────────────────────────────  
5) 🌐 WEBUI     Start Open WebUI + RAG
6) 🩺 DOCTOR    Auto-Repair & Audit
7) 📥 DOWNLOAD  1.58-bit Models
8) 🔄 REINSTALL Clean Deps & Build
9) ⚡ BENCHMARK Detect Best Backend  
──────────────────────────────────────  
10) 📦 MARKET    List available plugins
11) 📥 MARKET    Install a plugin
12) 🗑️  MARKET    Remove a plugin  
──────────────────────────────────────  
13) 💀 CACHE     Clean model cache
14) 📜 LOGS      View system logs
15) ❓ HELP      Troubleshooting Guide
16) 🚪 EXIT
Select [1-16]:  
-  
6) 🩺 DOCTOR    Auto-Repair & Audit  
🩺 BitNet Doctor: Auditing System Health...  
ℹ️  Some fixes require sudo and a session restart to take effect.  
✅ Group 'video' OK  
✅ Group 'render' OK  
✅ Intel oneAPI found (active compute GPU)  
ℹ️  AMD GPU also detected but Intel Arc takes priority — ROCm not required  
✅ Python venv present  
✅ venv packages OK  
✅ llama-bench binary found  
✨ Audit complete.  
-  
#Download a model  
7) 📥 DOWNLOAD  1.58-bit Models  
📥 BitNet Model Downloader  
  
  1) BitNet-b1.58-2B-4T        (recommended, wget/curl)
  2) BitNet-b1.58-Large        (wget/curl)
  3) Falcon3-7B-1.58bit        (HuggingFace snapshot)
  4) Llama-3.2-1B-1.58bit      (HuggingFace snapshot)
  5) BitNet-2B-4T full repo    (HuggingFace snapshot)
  6) Custom URL
  0) Cancel
Choice:
-  
-  
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



