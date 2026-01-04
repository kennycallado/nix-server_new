#!/usr/bin/env bash
# Instala NixOS en un servidor usando nixos-anywhere
# Uso: install.sh <host> [ip]
# Variables esperadas: AGE_BIN, NIXOS_ANYWHERE_BIN, JQ_BIN

set -e
HOST="${1:-}"
IP="${2:-}"

if [ -z "$HOST" ]; then
  echo "Uso: nix run .#install -- <host> [ip]"
  echo "Ejemplo: nix run .#install -- server_01"
  echo "         nix run .#install -- server_01 192.168.1.100  (override IP)"
  exit 1
fi

PROJECT_ROOT="$(pwd)"
SECRETS_DIR="$PROJECT_ROOT/secrets"
STATE_DIR="$PROJECT_ROOT/hosts/state"
NODES_FILE="$STATE_DIR/nodes.json"
AGE_FILE="$SECRETS_DIR/hosts/$HOST.age"
PUB_FILE="$SECRETS_DIR/hosts/$HOST.pub"

# Si no se proporciona IP, leerla de nodes.json
if [ -z "$IP" ]; then
  if [ ! -f "$NODES_FILE" ]; then
    echo "Error: No existe $NODES_FILE"
    echo "Crea el nodo primero o proporciona la IP manualmente."
    exit 1
  fi
  
  IP=$($JQ_BIN -r ".[\"$HOST\"].public_ip // empty" "$NODES_FILE")
  
  if [ -z "$IP" ]; then
    echo "Error: No se encontró IP para '$HOST' en $NODES_FILE"
    echo ""
    echo "Opciones:"
    echo "  1. Añade el nodo a nodes.json con su IP"
    echo "  2. Proporciona la IP manualmente: nix run .#install -- $HOST <ip>"
    echo ""
    echo "Nodos disponibles en $NODES_FILE:"
    $JQ_BIN -r 'keys[]' "$NODES_FILE" 2>/dev/null || echo "  (ninguno)"
    exit 1
  fi
  
  echo "IP obtenida de $NODES_FILE: $IP"
fi

if [ ! -f "$AGE_FILE" ] || [ ! -f "$PUB_FILE" ]; then
  echo "Error: No existen claves para $HOST"
  echo "Primero ejecuta: nix run .#keygen -- $HOST"
  exit 1
fi

echo "Verificando secretos..."

TOKEN_FILE="$SECRETS_DIR/services-k3s_token.age"
if [ ! -f "$TOKEN_FILE" ]; then
  echo "Error: No existe $TOKEN_FILE"
  echo "Créalo con: cd secrets && echo 'tu-token-secreto' | agenix -e services-k3s_token.age"
  exit 1
fi

TOKEN_CONTENT=$($AGE_BIN -d -i ~/.ssh/id_ed25519 "$TOKEN_FILE" 2>/dev/null || echo "")
if [ -z "$TOKEN_CONTENT" ]; then
  echo "Error: El secreto services-k3s_token.age está vacío o no se puede desencriptar"
  echo ""
  echo "Para regenerar el token:"
  echo "  cd secrets"
  echo "  head -c 32 /dev/urandom | base64 | agenix -e services-k3s_token.age"
  exit 1
fi
echo "Token k3s: OK ($(echo "$TOKEN_CONTENT" | wc -c) bytes)"

PASS_FILE="$SECRETS_DIR/users-admin_password.age"
if [ -f "$PASS_FILE" ]; then
  PASS_CONTENT=$($AGE_BIN -d -i ~/.ssh/id_ed25519 "$PASS_FILE" 2>/dev/null || echo "")
  if [ -z "$PASS_CONTENT" ]; then
    echo "Advertencia: users-admin_password.age está vacío o no se puede desencriptar"
  else
    echo "Password admin: OK"
  fi
fi

echo "Preparando instalación de $HOST ($IP)..."

EXTRA_FILES=$(mktemp -d)
trap "rm -rf $EXTRA_FILES" EXIT

install -d -m700 "$EXTRA_FILES/etc/ssh"
$AGE_BIN -d -i ~/.ssh/id_ed25519 "$AGE_FILE" > "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key"
chmod 600 "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key"
cp "$PUB_FILE" "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key.pub"
chmod 644 "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key.pub"

echo "Claves SSH preparadas"
echo "Instalando NixOS en $HOST ($IP)..."

$NIXOS_ANYWHERE_BIN \
  --flake ".#$HOST" \
  --extra-files "$EXTRA_FILES" \
  "root@$IP"

echo ""
echo "Instalación completada!"
echo "El servidor ya tiene las claves SSH correctas."
echo "Puedes hacer deploy directamente: nix run nixpkgs#deploy-rs -- .#$HOST"
