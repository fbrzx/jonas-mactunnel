#!/usr/bin/env bash
# Sync Jonas agent vault to local Obsidian vault
# Uses KEY_PATH, HOST, and JONAS_VAULT_PATH from .env

set -euo pipefail

AUTO_YES=false
[[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]] && AUTO_YES=true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load .env
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
	set -a
	source "${PROJECT_ROOT}/.env"
	set +a
fi

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

LOCAL_VAULT="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Jonas"
TEMP_VAULT="${JONAS_LOCAL_TMP_VAULT}"

echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       Jonas Vault Sync                     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""

# Check required env vars
missing=()
[[ -n "${KEY_PATH:-}" ]] || missing+=("KEY_PATH")
[[ -n "${HOST:-}" ]] || missing+=("HOST")
[[ -n "${JONAS_VAULT_PATH:-}" ]] || missing+=("JONAS_VAULT_PATH")
[[ -n "${JONAS_LOCAL_TMP_VAULT:-}" ]] || missing+=("JONAS_LOCAL_TMP_VAULT")

if (( ${#missing[@]} > 0 )); then
	echo -e "${RED}Missing required env var(s): ${missing[*]}${NC}"
	echo ""
	echo "Set these in ${PROJECT_ROOT}/.env:"
	echo "  KEY_PATH=/path/to/ssh/key"
	echo "  HOST=user@hostname"
	echo "  JONAS_VAULT_PATH=/path/to/vault/"
	echo "  JONAS_LOCAL_TMP_VAULT=/path/to/local/temp"
	exit 1
fi

SSH_OPTS=(-i "${KEY_PATH}" -o ConnectTimeout=5 -o BatchMode=yes)
REMOTE_PATH="${HOST}:${JONAS_VAULT_PATH}"

echo -e "Remote: ${BLUE}${REMOTE_PATH}${NC}"
echo -e "Local:  ${BLUE}${LOCAL_VAULT}/${NC}"
echo ""

# Create local vault dir if needed
mkdir -p "${LOCAL_VAULT}"

# Test write access to local vault
if ! touch "${LOCAL_VAULT}/.rsync-test" 2>/dev/null; then
	echo -e "${RED}Error: Cannot write to local vault directory${NC}"
	echo ""
	echo "The directory requires Full Disk Access permission:"
	echo "  ${LOCAL_VAULT}"
	echo ""
	echo "To fix this on macOS:"
	echo "  1. Open System Settings → Privacy & Security → Full Disk Access"
	echo "  2. Add your terminal app (Terminal.app or iTerm.app)"
	echo "  3. Restart your terminal and try again"
	echo ""
	echo "Or use a different local path by changing LOCAL_VAULT in this script"
	exit 1
fi
rm -f "${LOCAL_VAULT}/.rsync-test"

# Test SSH connection
echo -e "${BLUE}Testing connection...${NC}"
if ! ssh "${SSH_OPTS[@]}" "${HOST}" "ls ${JONAS_VAULT_PATH}" >/dev/null 2>&1; then
	echo -e "${RED}Error: Cannot connect to ${HOST} or vault path doesn't exist${NC}"
	echo ""
	echo "Troubleshooting:"
	echo "  ssh -i ${KEY_PATH} ${HOST}"
	echo "  ssh -i ${KEY_PATH} ${HOST} 'ls -la ${JONAS_VAULT_PATH}'"
	exit 1
fi
echo -e "${GREEN}✓ Connection successful${NC}"
echo ""

# Check for changes (dry-run)
echo -e "${BLUE}Checking for changes...${NC}"
mkdir -p "${TEMP_VAULT}"
DRY_RUN_OUTPUT=$(rsync -avz --dry-run -e "ssh -i ${KEY_PATH}" "${REMOTE_PATH}" "${TEMP_VAULT}/" 2>&1) || {
	echo -e "${RED}Error running rsync:${NC}"
	echo "$DRY_RUN_OUTPUT"
	exit 1
}

# Count files that would be transferred (excluding the summary lines)
CHANGES=$(echo "$DRY_RUN_OUTPUT" | grep -E "^\S" | grep -vE "^(sending|sent|total|building|$)" | wc -l | tr -d ' ')

if [[ "$CHANGES" -eq "0" ]]; then
	echo -e "${GREEN}✓ Already up to date${NC}"
	exit 0
fi

echo -e "${YELLOW}Found ${CHANGES} file(s) to sync:${NC}"
echo "$DRY_RUN_OUTPUT" | grep -E "^\S" | grep -vE "^(sending|sent|total|building|$)" | sed 's/^/  • /' | head -10
if [[ "$CHANGES" -gt 10 ]]; then
	echo "  ... and $(($CHANGES - 10)) more"
fi
echo ""

# Confirm sync
if [[ "$AUTO_YES" != true ]]; then
	read -p "$(echo -e "${YELLOW}Proceed with sync? [y/N]:${NC} ")" -n 1 -r
	echo
	if [[ ! $REPLY =~ ^[Yy]$ ]]; then
		echo "Sync cancelled"
		exit 0
	fi
fi

# Perform sync
echo -e "${BLUE}Syncing to temporary location...${NC}"
mkdir -p "${TEMP_VAULT}"
rsync -avz --progress -e "ssh -i ${KEY_PATH}" "${REMOTE_PATH}" "${TEMP_VAULT}/"

echo -e "${BLUE}Copying to iCloud vault...${NC}"
mkdir -p "${LOCAL_VAULT}"
# Note: Extended attributes (metadata) can't be copied to iCloud, but the files themselves copy fine
cp -Rv "${TEMP_VAULT}/" "${LOCAL_VAULT}/" 2>&1 | grep -v "unable to copy extended attributes" || true

echo ""
echo -e "${GREEN}✓ Vault synced to: ${LOCAL_VAULT}/${NC}"
