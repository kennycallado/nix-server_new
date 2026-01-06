#!/usr/bin/env bash
# Install full NixOS configuration using nixos-anywhere
# Usage: install.sh <host> [ip]
# Expected variables: AGE_BIN, NIXOS_ANYWHERE_BIN

set -e
HOST="${1:-}"
IP="${2:-}"

if [ -z "$HOST" ]; then
  echo "Usage: nix run .#install -- <host> [ip]"
  echo "Example: nix run .#install -- server-01"
  echo "         nix run .#install -- server-01 192.168.1.100  (override IP)"
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

# If IP not provided, read from config.nix
if [ -z "$IP" ]; then
  if [ ! -d "$NODES_DIR/$HOST" ]; then
    echo "Error: Host '$HOST' not found in hosts/nodes/"
    echo ""
    echo "Available hosts:"
    for dir in "$NODES_DIR"/*/; do
      echo "  - $(basename "$dir")"
    done
    exit 1
  fi

  IP=$(get_host_ip "$HOST")

  if [ -z "$IP" ] || [ "$IP" = "null" ]; then
    echo "Error: No IP configured for '$HOST'"
    echo ""
    echo "Set deploy.ip in hosts/nodes/$HOST/config.nix"
    exit 1
  fi

  echo "IP from config.nix: $IP"
fi

if [ ! -f "$AGE_FILE" ] || [ ! -f "$PUB_FILE" ]; then
  echo "Error: Keys not found for $HOST"
  echo "First run: nix run .#keygen -- $HOST"
  exit 1
fi

echo "Verifying secrets..."

TOKEN_FILE="$SECRETS_DIR/services-k3s_token.age"
if [ ! -f "$TOKEN_FILE" ]; then
  echo "Error: $TOKEN_FILE not found"
  echo "Create it with: cd secrets && echo 'your-secret-token' | agenix -e services-k3s_token.age"
  exit 1
fi

TOKEN_CONTENT=$($AGE_BIN -d -i ~/.ssh/id_ed25519 "$TOKEN_FILE" 2>/dev/null || echo "")
if [ -z "$TOKEN_CONTENT" ]; then
  echo "Error: services-k3s_token.age is empty or cannot be decrypted"
  echo ""
  echo "To regenerate the token:"
  echo "  cd secrets"
  echo "  head -c 32 /dev/urandom | base64 | agenix -e services-k3s_token.age"
  exit 1
fi
echo "K3s token: OK ($(echo "$TOKEN_CONTENT" | wc -c) bytes)"

PASS_FILE="$SECRETS_DIR/users-admin_password.age"
if [ -f "$PASS_FILE" ]; then
  PASS_CONTENT=$($AGE_BIN -d -i ~/.ssh/id_ed25519 "$PASS_FILE" 2>/dev/null || echo "")
  if [ -z "$PASS_CONTENT" ]; then
    echo "Warning: users-admin_password.age is empty or cannot be decrypted"
  else
    echo "Admin password: OK"
  fi
fi

echo "Preparing installation of $HOST ($IP)..."

EXTRA_FILES=$(mktemp -d)
trap "rm -rf $EXTRA_FILES" EXIT

install -d -m700 "$EXTRA_FILES/etc/ssh"
$AGE_BIN -d -i ~/.ssh/id_ed25519 "$AGE_FILE" >"$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key"
chmod 600 "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key"
cp "$PUB_FILE" "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key.pub"
chmod 644 "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key.pub"

echo "SSH keys prepared"
echo "Installing NixOS on $HOST ($IP)..."

$NIXOS_ANYWHERE_BIN \
  --flake ".#$HOST" \
  --extra-files "$EXTRA_FILES" \
  "root@$IP"

echo ""
echo "Installation completed!"
echo "The server now has the correct SSH keys."
echo "You can deploy directly: nix run .#deploy -- $HOST"
