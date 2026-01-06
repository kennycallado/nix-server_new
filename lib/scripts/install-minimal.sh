#!/usr/bin/env bash
# Install minimal NixOS configuration using nixos-anywhere (Phase 1)
# Usage: install-minimal.sh <hostname>
# Expected variables: AGE_BIN, NIXOS_ANYWHERE_BIN

set -e

HOST="${1:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Verify required binaries
: "${AGE_BIN:?AGE_BIN not set}"
: "${NIXOS_ANYWHERE_BIN:?NIXOS_ANYWHERE_BIN not set}"

if [ -z "$HOST" ]; then
  echo "Usage: nix run .#install-minimal -- <hostname>"
  echo ""
  echo "Installs minimal configuration (Phase 1) on a remote server."
  echo "This configuration includes only basics: SSH, disk partitioning, bootstrap."
  echo ""
  echo "Example: nix run .#install-minimal -- server-01"
  exit 1
fi

PROJECT_ROOT="$(pwd)"
SECRETS_DIR="$PROJECT_ROOT/secrets"
NODES_DIR="$PROJECT_ROOT/hosts/nodes"
AGE_FILE="$SECRETS_DIR/hosts/$HOST.age"
PUB_FILE="$SECRETS_DIR/hosts/$HOST.pub"

# Get IP from deploy-rs config via nix eval
get_host_ip() {
  local host="$1"
  nix eval --raw ".#deploy.nodes.${host}.hostname" 2>/dev/null || echo ""
}

# =============================================================================
# Validate host exists
# =============================================================================
log_info "Validating configuration for '$HOST'..."

if [ ! -d "$NODES_DIR/$HOST" ]; then
  log_error "Host '$HOST' not found in hosts/nodes/"
  echo ""
  echo "Available hosts:"
  for dir in "$NODES_DIR"/*/; do
    echo "  - $(basename "$dir")"
  done
  exit 1
fi

IP=$(get_host_ip "$HOST")

if [ -z "$IP" ] || [ "$IP" = "null" ]; then
  log_error "No IP configured for '$HOST'"
  echo ""
  echo "Set deploy.ip in hosts/nodes/$HOST/config.nix"
  exit 1
fi

log_success "Host found: $HOST ($IP)"

# =============================================================================
# Verify SSH keys exist
# =============================================================================
log_info "Verifying SSH keys..."

if [ ! -f "$AGE_FILE" ]; then
  log_error "Private key not found: $AGE_FILE"
  echo ""
  echo "Generate keys first:"
  echo "  nix run .#keygen -- $HOST"
  exit 1
fi

if [ ! -f "$PUB_FILE" ]; then
  log_error "Public key not found: $PUB_FILE"
  echo ""
  echo "Generate keys first:"
  echo "  nix run .#keygen -- $HOST"
  exit 1
fi

log_success "SSH keys found"

# =============================================================================
# Prepare extra files (SSH keys for injection)
# =============================================================================
log_info "Preparing files for injection..."

EXTRA_FILES=$(mktemp -d)
trap "rm -rf $EXTRA_FILES" EXIT

# Create SSH directory with correct permissions
install -d -m700 "$EXTRA_FILES/etc/ssh"

# Decrypt host private key
log_info "Decrypting host SSH key..."
if ! $AGE_BIN -d -i ~/.ssh/id_ed25519 "$AGE_FILE" >"$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key" 2>/dev/null; then
  log_error "Could not decrypt $AGE_FILE"
  echo ""
  echo "Verify you have access to ~/.ssh/id_ed25519"
  exit 1
fi
chmod 600 "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key"

# Copy public key
cp "$PUB_FILE" "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key.pub"
chmod 644 "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key.pub"

log_success "SSH keys prepared for injection"

# =============================================================================
# Run nixos-anywhere with minimal configuration
# =============================================================================
log_info "Installing minimal configuration on $HOST ($IP)..."
echo ""
echo "  Flake:  .#$HOST-minimal"
echo "  Target: root@$IP"
echo ""

$NIXOS_ANYWHERE_BIN \
  --flake ".#$HOST-minimal" \
  --extra-files "$EXTRA_FILES" \
  "root@$IP"

# =============================================================================
# Completion
# =============================================================================
echo ""
log_success "Minimal installation completed!"
echo ""
echo "Server '$HOST' now has:"
echo "  - Disk partitioning configured"
echo "  - Base NixOS system"
echo "  - Host SSH keys installed"
echo "  - SSH access enabled"
echo ""
echo "Next steps (Phase 2):"
echo "  - Deploy full configuration: nix run .#deploy -- $HOST"
echo ""
