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
rsW1uBbX4lpci2txLa7F9Xav/wPCe8VKABgBAA==