#!/usr/bin/env bash
# Deploy NixOS configuration to hosts using deploy-rs with remote build
# Usage: deploy.sh <hostname> | --all

set -e

HOST="${1:-}"

if [ -z "$HOST" ]; then
  echo "Usage: nix run .#deploy -- <hostname>"
  echo "       nix run .#deploy -- --all"
  echo ""
  echo "Examples:"
  echo "  nix run .#deploy -- server-01    # Deploy to a specific host"
  echo "  nix run .#deploy -- --all        # Deploy to all hosts"
  echo ""
  echo "Note: Build runs on the remote server (remoteBuild=true)"
  exit 1
fi

PROJECT_ROOT="$(pwd)"
NODES_DIR="$PROJECT_ROOT/hosts/nodes"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}info${NC} $1"; }
log_success() { echo -e "${GREEN}ok${NC} $1"; }
log_warn() { echo -e "${YELLOW}warn${NC} $1"; }
log_error() { echo -e "${RED}error${NC} $1"; }

# Get IP from deploy-rs config via nix eval
get_host_ip() {
  local host="$1"
  nix eval --raw ".#deploy.nodes.${host}.hostname" 2>/dev/null || echo ""
}

# Get all configured hosts from hosts/nodes/*/
get_all_hosts() {
  for dir in "$NODES_DIR"/*/; do
    basename "$dir"
  done
}

# Deploy a single host
deploy_host() {
  local target_host="$1"

  # Check host exists
  if [ ! -d "$NODES_DIR/$target_host" ]; then
    log_error "Host '$target_host' not found in hosts/nodes/"
    echo ""
    echo "Available hosts:"
    get_all_hosts | sed 's/^/  - /'
    return 1
  fi

  # Get IP from config.nix
  local host_ip
  host_ip=$(get_host_ip "$target_host")

  if [ -z "$host_ip" ] || [ "$host_ip" = "null" ]; then
    log_error "No IP configured for '$target_host'"
    echo ""
    echo "Set deploy.ip in hosts/nodes/$target_host/config.nix"
    return 1
  fi

  echo ""
  echo "=========================================="
  log_info "Deploying $target_host"
  echo "=========================================="
  echo "  IP: $host_ip"
  echo ""

  log_info "Starting deploy with remote build..."
  echo ""

  # Run deploy-rs
  if nix run nixpkgs#deploy-rs -- ".#$target_host"; then
    log_success "Deploy completed for $target_host"
    return 0
  else
    log_error "Deploy failed for $target_host"
    return 1
  fi
}

# --all mode: deploy to all hosts
if [ "$HOST" = "--all" ]; then
  log_info "Deploying to all hosts..."

  HOSTS=$(get_all_hosts)

  if [ -z "$HOSTS" ]; then
    log_error "No hosts found in hosts/nodes/"
    exit 1
  fi

  HOST_COUNT=$(echo "$HOSTS" | wc -l)
  log_info "Found $HOST_COUNT host(s)"

  FAILED_HOSTS=()
  SUCCESS_HOSTS=()

  for h in $HOSTS; do
    if deploy_host "$h"; then
      SUCCESS_HOSTS+=("$h")
    else
      FAILED_HOSTS+=("$h")
    fi
  done

  # Summary
  echo ""
  echo "=========================================="
  echo "DEPLOY SUMMARY"
  echo "=========================================="

  if [ ${#SUCCESS_HOSTS[@]} -gt 0 ]; then
    log_success "Successful (${#SUCCESS_HOSTS[@]}):"
    for h in "${SUCCESS_HOSTS[@]}"; do
      echo "    - $h"
    done
  fi

  if [ ${#FAILED_HOSTS[@]} -gt 0 ]; then
    log_error "Failed (${#FAILED_HOSTS[@]}):"
    for h in "${FAILED_HOSTS[@]}"; do
      echo "    - $h"
    done
    exit 1
  fi

  echo ""
  log_success "All deploys completed successfully!"
  exit 0
fi

# Normal mode: deploy to specific host
if deploy_host "$HOST"; then
  echo ""
  echo "=========================================="
  log_success "Deploy completed!"
  echo "=========================================="
  exit 0
else
  exit 1
fi
