#!/usr/bin/env bash
# status.sh - Show cluster status crossing local state with Hetzner
# Usage: nix run .#status
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

# Check required binaries
: "${HCLOUD_BIN:?HCLOUD_BIN not set}"
: "${JQ_BIN:?JQ_BIN not set}"

# Check if nodes.json exists
if [[ ! -f "$NODES_FILE" ]]; then
  echo -e "${RED}Error: $NODES_FILE not found${NC}" >&2
  exit 1
fi

# Read local state
LOCAL_STATE=$($JQ_BIN '.' "$NODES_FILE")

# Check if HCLOUD_TOKEN is set
HCLOUD_AVAILABLE=false
HETZNER_SERVERS="{}"

if [[ -n "${HCLOUD_TOKEN:-}" ]]; then
  # Try to get Hetzner servers
  if HETZNER_RAW=$($HCLOUD_BIN server list -o json 2>/dev/null); then
    HCLOUD_AVAILABLE=true
    # Transform hcloud output to a map by name
    HETZNER_SERVERS=$(echo "$HETZNER_RAW" | $JQ_BIN '
            map({
                (.name): {
                    id: .id,
                    status: .status,
                    ip: .public_net.ipv4.ip,
                    type: .server_type.name,
                    location: .datacenter.location.name
                }
            }) | add // {}
        ')
  else
    echo -e "${YELLOW}Warning: Failed to query Hetzner API${NC}" >&2
  fi
else
  echo -e "${YELLOW}Warning: HCLOUD_TOKEN not set, skipping Hetzner queries${NC}" >&2
fi

# Get all node names (local + remote)
ALL_NODES=$(echo "$LOCAL_STATE" "$HETZNER_SERVERS" | $JQ_BIN -s '
    (.[0] | keys) + (.[1] | keys) | unique | sort
')

# Build the final status object
RESULT=$($JQ_BIN -n \
  --argjson local "$LOCAL_STATE" \
  --argjson remote "$HETZNER_SERVERS" \
  --argjson nodes "$ALL_NODES" \
  --argjson hcloud_available "$HCLOUD_AVAILABLE" \
  '
    $nodes | map(. as $name |
        {
            ($name): {
                local: (
                    if $local[$name] then
                        {
                            provider: $local[$name].provider,
                            type: $local[$name].type,
                            location: $local[$name].location,
                            ip: $local[$name].public_ip,
                            provider_id: $local[$name].provider_id,
                            status: $local[$name].status
                        }
                    else
                        null
                    end
                ),
                remote: (
                    if $local[$name].provider == "manual" then
                        "skip"
                    elif $local[$name].provider == "hetzner" or ($local[$name] | not) then
                        if $hcloud_available then
                            if $remote[$name] then
                                {
                                    status: $remote[$name].status,
                                    ip: $remote[$name].ip,
                                    id: $remote[$name].id
                                }
                            else
                                null
                            end
                        else
                            "unavailable"
                        end
                    else
                        "skip"
                    end
                ),
                synced: (
                    if $local[$name].provider == "manual" then
                        true
                    elif ($local[$name] | not) then
                        false
                    elif ($remote[$name] | not) and $hcloud_available then
                        false
                    elif $hcloud_available and $remote[$name] then
                        ($local[$name].public_ip == $remote[$name].ip) and
                        ($local[$name].status == $remote[$name].status)
                    else
                        null
                    end
                )
            }
        }
    ) | add // {}
')

# Output JSON result
echo "$RESULT" | $JQ_BIN '.'

# Print summary to stderr
TOTAL=$(echo "$ALL_NODES" | $JQ_BIN 'length')
SYNCED=$(echo "$RESULT" | $JQ_BIN '[.[] | select(.synced == true)] | length')
UNSYNCED=$(echo "$RESULT" | $JQ_BIN '[.[] | select(.synced == false)] | length')
UNKNOWN=$(echo "$RESULT" | $JQ_BIN '[.[] | select(.synced == null)] | length')

echo "" >&2
echo -e "Summary: ${GREEN}$SYNCED synced${NC}, ${RED}$UNSYNCED unsynced${NC}, ${YELLOW}$UNKNOWN unknown${NC} (total: $TOTAL)" >&2
