#!/usr/bin/env bash
# Genera claves SSH para un host y las encripta con agenix
# Uso: keygen.sh <host>
# Variables esperadas: ADMIN_SSH_KEY, AGE_BIN, SSH_KEYGEN_BIN, AGENIX_BIN, SCRIPT_BIN

set -e
HOST="${1:-}"

if [ -z "$HOST" ]; then
  echo "Uso: nix run .#keygen -- <host>"
  echo "Ejemplo: nix run .#keygen -- server_01"
  exit 1
fi

SECRETS_DIR="$(pwd)/secrets"
HOSTS_DIR="$SECRETS_DIR/hosts"
KEY_FILE="$HOSTS_DIR/$HOST"
AGE_FILE="$HOSTS_DIR/$HOST.age"
PUB_FILE="$HOSTS_DIR/$HOST.pub"

if [ ! -d "$HOSTS_DIR" ]; then
  echo "Error: No existe el directorio $HOSTS_DIR"
  exit 1
fi

if [ -f "$PUB_FILE" ]; then
  echo "Ya existe clave para $HOST en $PUB_FILE"
  echo "Contenido: $(cat "$PUB_FILE")"
  read -p "¿Regenerar? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
  fi
fi

echo "Generando claves SSH para $HOST..."

TEMP_KEY=$(mktemp)
$SSH_KEYGEN_BIN -t ed25519 -f "$TEMP_KEY" -N "" -C "root@$HOST" -q

cp "$TEMP_KEY.pub" "$PUB_FILE"
echo "Clave pública guardada en: $PUB_FILE"

echo "Encriptando clave privada con agenix..."
cd "$SECRETS_DIR"
cat "$TEMP_KEY" | $AGE_BIN -R <(echo "$ADMIN_SSH_KEY") -o "$AGE_FILE"

rm -f "$TEMP_KEY" "$TEMP_KEY.pub"

echo ""
echo "Claves generadas para $HOST:"
echo "  Pública: $PUB_FILE"
echo "  Privada (encriptada): $AGE_FILE"
echo ""
echo "Clave pública:"
cat "$PUB_FILE"
echo ""

echo "Re-encriptando secretos para incluir la nueva clave del host..."
$SCRIPT_BIN -q -c "$AGENIX_BIN -r" /dev/null

echo ""
echo "Claves generadas y secretos actualizados para $HOST"
