#!/usr/bin/env bash
# TEST SCRIPT: Verify Hetzner connectivity
# Expected vars: HCLOUD_BIN, JQ_BIN, AGE_BIN

set -e

# Set defaults if running manually in devShell
HCLOUD_BIN="${HCLOUD_BIN:-hcloud}"
JQ_BIN="${JQ_BIN:-jq}"
AGE_BIN="${AGE_BIN:-age}"

# Check for required binaries if using defaults
if ! command -v "$HCLOUD_BIN" >/dev/null; then
  echo "❌ Error: $HCLOUD_BIN not found."
  exit 1
fi

TOKEN_FILE="$(pwd)/secrets/hcloud-token.age"

if [ -n "$HCLOUD_TOKEN" ]; then
  echo "ℹ️  Usando HCLOUD_TOKEN ya definido en el entorno."
else
  echo "🔓 Intentando desencriptar $TOKEN_FILE..."
  # Check for age binary before trying to use it
  if ! command -v "$AGE_BIN" >/dev/null; then
    echo "❌ Error: $AGE_BIN not found. Cannot decrypt token."
    exit 1
  fi

  HCLOUD_TOKEN=$($AGE_BIN -d -i ~/.ssh/id_ed25519 "$TOKEN_FILE" 2>/dev/null || echo "")
fi

if [ -z "$HCLOUD_TOKEN" ]; then
  echo "❌ Fallo al desencriptar o token vacío. ¿Tienes acceso a la clave privada ~/.ssh/id_ed25519?"
  exit 1
fi
export HCLOUD_TOKEN

echo "✅ Token obtenido."
echo "📡 Listando servidores en Hetzner (prueba de API)..."

$HCLOUD_BIN server list

echo "🎉 ¡Funciona! El script tiene acceso correcto a la API."
