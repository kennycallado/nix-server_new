#!/usr/bin/env bash
# TEST SCRIPT: Verify Hetzner connectivity
# Expected vars: HCLOUD_BIN, JQ_BIN, AGE_BIN

set -e

SECRETS_DIR="$(pwd)/secrets"
TOKEN_FILE="$SECRETS_DIR/hcloud-token.age"

echo "🔓 Intentando desencriptar $TOKEN_FILE..."
HCLOUD_TOKEN=$($AGE_BIN -d -i ~/.ssh/id_ed25519 "$TOKEN_FILE" 2>/dev/null || echo "")

if [ -z "$HCLOUD_TOKEN" ]; then
  echo "❌ Fallo al desencriptar. ¿Tienes acceso a la clave privada ~/.ssh/id_ed25519?"
  exit 1
fi
export HCLOUD_TOKEN

echo "✅ Token obtenido."
echo "📡 Listando servidores en Hetzner (prueba de API)..."

$HCLOUD_BIN server list

echo "🎉 ¡Funciona! El script tiene acceso correcto a la API."