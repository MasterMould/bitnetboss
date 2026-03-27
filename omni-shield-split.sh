#!/bin/bash
# =================================================================
# 🛡️ BITNET b1.58 OMNI-SHIELD WORKSTATION (2026.8)
# =================================================================
# Self-extracting single-file launcher.
# On first run, lib/ modules are extracted from the embedded payload.
# Subsequent runs load from lib/ directly — extraction is skipped.
# =================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# ================================================================
# SELF-EXTRACTION: write lib/ from embedded payload if missing
# ================================================================
_extract_libs() {
    echo "📦 First run — extracting lib modules..."
    mkdir -p "$LIB_DIR"
    local PAYLOAD_START
    PAYLOAD_START=$(grep -n '^# __PAYLOAD_START__$' "$0" | cut -d: -f1)
    if [[ -z "$PAYLOAD_START" ]]; then
        echo "❌ Payload marker not found — file may be corrupted."
        exit 1
    fi
    tail -n +"$((PAYLOAD_START + 1))" "$0" | base64 -d | tar xzf - -C "$SCRIPT_DIR" || {
        echo "❌ Extraction failed."; exit 1
    }
    shopt -s nullglob
    local extracted=("$LIB_DIR"/[0-9][0-9]-*.sh)
    shopt -u nullglob
    [[ ${#extracted[@]} -eq 0 ]] && { echo "❌ No modules extracted."; exit 1; }
    chmod +x "${extracted[@]}"
    echo "✅ Extracted ${#extracted[@]} modules to $LIB_DIR"
}

# ================================================================
# LOAD MODULES
# ================================================================
shopt -s nullglob
_libs=("$LIB_DIR"/[0-9][0-9]-*.sh)
shopt -u nullglob

[[ ${#_libs[@]} -eq 0 ]] && _extract_libs

shopt -s nullglob
_libs=("$LIB_DIR"/[0-9][0-9]-*.sh)
shopt -u nullglob

[[ ${#_libs[@]} -eq 0 ]] && { echo "❌ No lib modules found in $LIB_DIR"; exit 1; }

for _lib in "${_libs[@]}"; do
    source "$_lib" || { echo "❌ Failed to load $(basename "$_lib")"; exit 1; }
done
unset _lib _libs

mkdir -p "$LOG_DIR" "$PLUGIN_DIR" "$MARKET_DIR"
[[ -z "$(ls -A "$PLUGIN_DIR" 2>/dev/null)" ]] && create_default_plugins

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

# __PAYLOAD_START__
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
ikNBrgAYAQA=