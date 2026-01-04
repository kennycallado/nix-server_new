#!/usr/bin/env bash
# destroy.sh - Destroy a node and clean up local state
# Usage: nix run .#destroy -- <hostname>
#
# Required env vars (injected by apps.nix):
#   HCLOUD_BIN - path to hcloud binary
#   JQ_BIN     - path to jq binary

set -euo pipefail

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NODES_FILE="$FLAKE_ROOT/hosts/state/nodes.json"
WIREGUARD_FILE="$FLAKE_ROOT/hosts/state/wireguard.json"

# Check required binaries
: "${HCLOUD_BIN:?HCLOUD_BIN not set}"
: "${JQ_BIN:?JQ_BIN not set}"

# ------------------------------------------------------------------------------
# Validate arguments
# ------------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
    echo -e "${RED}Error: Missing hostname argument${NC}" >&2
    echo "Usage: nix run .#destroy -- <hostname>" >&2
    exit 1
fi

HOSTNAME="$1"

# ------------------------------------------------------------------------------
# Read node state
# ------------------------------------------------------------------------------
if [[ ! -f "$NODES_FILE" ]]; then
    echo -e "${RED}Error: $NODES_FILE not found${NC}" >&2
    exit 1
fi

# Check if node exists in nodes.json
NODE_EXISTS=$($JQ_BIN --arg h "$HOSTNAME" 'has($h)' "$NODES_FILE")
if [[ "$NODE_EXISTS" != "true" ]]; then
    echo -e "${RED}Error: Node '$HOSTNAME' not found in $NODES_FILE${NC}" >&2
    echo "Available nodes:" >&2
    $JQ_BIN -r 'keys[]' "$NODES_FILE" | sed 's/^/  - /' >&2
    exit 1
fi

# Get node data
NODE_DATA=$($JQ_BIN --arg h "$HOSTNAME" '.[$h]' "$NODES_FILE")
PROVIDER=$(echo "$NODE_DATA" | $JQ_BIN -r '.provider')
PROVIDER_ID=$(echo "$NODE_DATA" | $JQ_BIN -r '.provider_id // empty')
PUBLIC_IP=$(echo "$NODE_DATA" | $JQ_BIN -r '.public_ip // "unknown"')

# ------------------------------------------------------------------------------
# Check k3s role - abort if server
# ------------------------------------------------------------------------------
CONFIG_FILE="$FLAKE_ROOT/hosts/nodes/$HOSTNAME/config.nix"
if [[ -f "$CONFIG_FILE" ]]; then
    # Parse k3s.role from Nix config (simple grep approach)
    if grep -q 'k3s\.role.*=.*"server"' "$CONFIG_FILE" 2>/dev/null || \
       grep -q "k3s\.role.*=.*'server'" "$CONFIG_FILE" 2>/dev/null || \
       (grep -A5 'k3s\s*=' "$CONFIG_FILE" 2>/dev/null | grep -q 'role\s*=\s*"server"'); then
        echo -e "${RED}ERROR: Cannot destroy k3s server node '$HOSTNAME'${NC}" >&2
        echo "" >&2
        echo "First drain the node and remove from cluster:" >&2
        echo "  kubectl drain $HOSTNAME --ignore-daemonsets --delete-emptydir-data" >&2
        echo "  kubectl delete node $HOSTNAME" >&2
        echo "" >&2
        echo "Then re-run this command." >&2
        exit 1
    fi
fi

# ------------------------------------------------------------------------------
# Confirmation
# ------------------------------------------------------------------------------
echo -e "${YELLOW}WARNING: This will destroy server '$HOSTNAME' (IP: $PUBLIC_IP)${NC}"
echo -e "Provider: $PROVIDER"
[[ -n "$PROVIDER_ID" ]] && echo -e "Provider ID: $PROVIDER_ID"
echo ""
read -rp "Type the hostname to confirm: " CONFIRM

if [[ "$CONFIRM" != "$HOSTNAME" ]]; then
    echo -e "${RED}Confirmation failed. Aborting.${NC}" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# Delete from Hetzner (if applicable)
# ------------------------------------------------------------------------------
if [[ "$PROVIDER" == "hetzner" ]]; then
    # Check HCLOUD_TOKEN
    if [[ -z "${HCLOUD_TOKEN:-}" ]]; then
        echo -e "${RED}Error: HCLOUD_TOKEN is required for Hetzner provider${NC}" >&2
        exit 1
    fi

    echo ""
    echo -e "Deleting server from Hetzner..."
    
    # Try to delete by provider_id first, fallback to name
    if [[ -n "$PROVIDER_ID" && "$PROVIDER_ID" != "null" ]]; then
        if $HCLOUD_BIN server delete "$PROVIDER_ID" 2>/dev/null; then
            echo -e "${GREEN}Server deleted by ID ($PROVIDER_ID)${NC}"
        else
            echo -e "${YELLOW}Warning: Could not delete by ID, trying by name...${NC}" >&2
            if $HCLOUD_BIN server delete "$HOSTNAME" 2>/dev/null; then
                echo -e "${GREEN}Server deleted by name ($HOSTNAME)${NC}"
            else
                echo -e "${YELLOW}Warning: Server not found in Hetzner (may already be deleted)${NC}" >&2
            fi
        fi
    else
        if $HCLOUD_BIN server delete "$HOSTNAME" 2>/dev/null; then
            echo -e "${GREEN}Server deleted by name ($HOSTNAME)${NC}"
        else
            echo -e "${YELLOW}Warning: Server not found in Hetzner (may already be deleted)${NC}" >&2
        fi
    fi
elif [[ "$PROVIDER" == "manual" ]]; then
    echo ""
    echo -e "${YELLOW}Provider is 'manual' - skipping cloud deletion${NC}"
else
    echo ""
    echo -e "${YELLOW}Unknown provider '$PROVIDER' - skipping cloud deletion${NC}"
fi

# ------------------------------------------------------------------------------
# Clean up local state
# ------------------------------------------------------------------------------
echo ""
echo "Cleaning up local state..."

# Remove from nodes.json
if [[ -f "$NODES_FILE" ]]; then
    $JQ_BIN --arg h "$HOSTNAME" 'del(.[$h])' "$NODES_FILE" > "$NODES_FILE.tmp"
    mv "$NODES_FILE.tmp" "$NODES_FILE"
    echo -e "  ${GREEN}Removed from nodes.json${NC}"
fi

# Remove from wireguard.json
if [[ -f "$WIREGUARD_FILE" ]]; then
    # Check if node exists in wireguard.json before removing
    WG_EXISTS=$($JQ_BIN --arg h "$HOSTNAME" 'has($h)' "$WIREGUARD_FILE")
    if [[ "$WG_EXISTS" == "true" ]]; then
        $JQ_BIN --arg h "$HOSTNAME" 'del(.[$h])' "$WIREGUARD_FILE" > "$WIREGUARD_FILE.tmp"
        mv "$WIREGUARD_FILE.tmp" "$WIREGUARD_FILE"
        echo -e "  ${GREEN}Removed from wireguard.json${NC}"
    else
        echo -e "  ${YELLOW}Not found in wireguard.json (skipped)${NC}"
    fi
fi

# ------------------------------------------------------------------------------
# Git commit
# ------------------------------------------------------------------------------
echo ""
echo "Committing state changes..."

cd "$FLAKE_ROOT"
git add hosts/state/
if git diff --cached --quiet hosts/state/; then
    echo -e "${YELLOW}No changes to commit${NC}"
else
    git commit -m "destroy: removed $HOSTNAME"
    echo -e "${GREEN}Committed state changes${NC}"
fi

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}Successfully destroyed '$HOSTNAME'${NC}"
echo ""
echo -e "${YELLOW}Note: Config files and secrets were preserved:${NC}"
echo "  - hosts/nodes/$HOSTNAME/config.nix"
echo "  - secrets/hosts/$HOSTNAME.age"
echo "  - secrets/wireguard-$HOSTNAME.age"
echo ""
echo "To fully remove, manually delete these files and re-run 'nix run .#rekey'"
