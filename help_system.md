# 🆘 BitNet Omni-Help & Troubleshooting Guide

## 🔧 Hardware Specifics

### Intel Arc A770 (oneAPI/SYCL)
* **Issue:** "icpx: command not found"
  * **Fix:** Run `source /opt/intel/oneapi/setvars.sh`. The script attempts this, but manual sourcing may be needed after a fresh reboot.
* **Issue:** GPU not detected.
  * **Fix:** Ensure your user is in the `render` group: `sudo usermod -aG render $USER`.

### AMD Radeon RX 570 (ROCm/HIP)
* **Issue:** "HIP Error: No binary found for gfx803"
  * **Fix:** The script targets `gfx803` specifically for Polaris. Ensure `rocm-dev` is installed via `sudo apt install rocm-dev`.
* **Issue:** Permission Denied.
  * **Fix:** `sudo usermod -aG video $USER`.

## 📄 File Processing
* **Supported:** .pdf, .docx, .csv, .xlsx, .md, .txt.
* **Large Files:** If a file exceeds 4000 characters, the script trims it to fit the 1.58-bit model's current context window to prevent "hallucination" or memory crashes.

## 🎙️ Voice & Vision
* **Voice:** Uses Whisper for STT and Piper for TTS. If no audio is heard, check `pavucontrol` to ensure the "Piper" output isn't muted.
* **Vision:** Requires a BitVLA-compatible model. Standard 2B models cannot "see" without the vision-encoder weights loaded.

## 💾 Logging
* All history is stored in `./chat_logs/history.log`.
* To clear logs: `rm ./chat_logs/*.log`.
