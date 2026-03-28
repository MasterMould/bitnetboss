#!/bin/bash
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && echo "Source this file, dont run it directly." && exit 1
# ================================================================
# 11-tools.sh — Log viewer and cache cleaner
# Requires: 00-globals.sh
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
