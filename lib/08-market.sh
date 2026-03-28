#!/bin/bash
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && echo "Source this file, dont run it directly." && exit 1
# ================================================================
# 08-market.sh — Local plugin marketplace
# Requires: 00-globals.sh, 07-plugins.sh
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
