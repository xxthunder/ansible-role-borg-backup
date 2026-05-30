#!/usr/bin/env bash
#
# Fetch the SSH host keys of a remote borg repo host and emit them in the YAML
# format consumed by this role's `borg_backup_remote_known_hosts` list.
#
# This script intentionally does NOT modify any inventory or group_vars file.
# Cross-check the printed SHA256 fingerprints against the provider's published
# host-key fingerprints before pasting the YAML block — auto-trusting whatever
# answers on first connect defeats the entire point of pinning.
#
# Usage:
#   fetch_remote_host_keys.sh <host>[:<port>]
#
# Examples:
#   fetch_remote_host_keys.sh backup.example.com         # port 22
#   fetch_remote_host_keys.sh backup.example.com:23      # non-standard port

set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  echo -e "${RED}No host given.${NC}" >&2
  echo "Usage: $0 <host>[:<port>]" >&2
  exit 1
fi

HOST="${TARGET%:*}"
PORT="${TARGET##*:}"
[[ "$HOST" == "$PORT" ]] && PORT=22

echo -e "${CYAN}Fetching SSH host keys from ${HOST}:${PORT}...${NC}"
echo

KEYS="$(ssh-keyscan -p "$PORT" -t ed25519,rsa "$HOST" 2>/dev/null || true)"
if [[ -z "$KEYS" ]]; then
  echo -e "${RED}ssh-keyscan returned no keys. Network problem or wrong host?${NC}" >&2
  exit 2
fi

echo -e "${YELLOW}Cross-check these SHA256 fingerprints against the provider's${NC}"
echo -e "${YELLOW}published host-key list before trusting them:${NC}"
echo
echo "$KEYS" | ssh-keygen -l -f -
echo
echo -e "${YELLOW}Only paste the YAML lines below if every fingerprint matches.${NC}"
echo

echo -e "${GREEN}--- copy from here ---${NC}"
echo "borg_backup_remote_known_hosts:"
while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^# ]] && continue
  echo "  - \"$line\""
done <<< "$KEYS"
echo -e "${GREEN}--- to here ---${NC}"
