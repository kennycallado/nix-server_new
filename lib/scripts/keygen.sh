#!/usr/bin/env bash
# Genera claves SSH y WireGuard para un host y las encripta con agenix
# Uso: keygen.sh [--force] <host>
# Variables esperadas: ADMIN_SSH_KEY, AGE_BIN, SSH_KEYGEN_BIN, AGENIX_BIN, SCRIPT_BIN, WG_BIN, JQ_BIN
#
# Si las claves ya existen:
#   - Sin --force: sincroniza wireguard.json con las claves existentes (no regenera)
#   - Con --force: regenera todas las claves

set -e

# Parse argumentos
FORCE=false
HOST=""
for arg in "$@"; do
  case $arg in
  --force)
    FORCE=true
    ;;
  *)
    HOST="$arg"
    ;;
  esac
done

if [ -z "$HOST" ]; then
  echo "Uso: nix run .#keygen -- [--force] <host>"
  echo "Ejemplo: nix run .#keygen -- server-01"
  echo ""
  echo "Opciones:"
  echo "  --force   Regenerar claves aunque ya existan"
  exit 1
fi

PROJECT_ROOT="$(pwd)"
SECRETS_DIR="$PROJECT_ROOT/secrets"
HOSTS_DIR="$SECRETS_DIR/hosts"
STATE_DIR="$PROJECT_ROOT/hosts/state"
KEY_FILE="$HOSTS_DIR/$HOST"
AGE_FILE="$HOSTS_DIR/$HOST.age"
PUB_FILE="$HOSTS_DIR/$HOST.pub"
WG_AGE_FILE="$SECRETS_DIR/wireguard-$HOST.age"
WG_PUB_FILE="$SECRETS_DIR/wireguard-$HOST.pub"
WG_STATE_FILE="$STATE_DIR/wireguard.json"

if [ ! -d "$HOSTS_DIR" ]; then
  echo "Error: No existe el directorio $HOSTS_DIR"
  exit 1
fi

if [ ! -d "$STATE_DIR" ]; then
  echo "Error: No existe el directorio $STATE_DIR"
  exit 1
fi

# =============================================================================
# Verificar si las claves ya existen
# =============================================================================
SSH_EXISTS=false
WG_EXISTS=false

if [ -f "$PUB_FILE" ] && [ -f "$AGE_FILE" ]; then
  SSH_EXISTS=true
fi

if [ -f "$WG_PUB_FILE" ] && [ -f "$WG_AGE_FILE" ]; then
  WG_EXISTS=true
fi

# Si ambas claves existen y no es --force, solo sincronizar wireguard.json
if [ "$SSH_EXISTS" = true ] && [ "$WG_EXISTS" = true ] && [ "$FORCE" = false ]; then
  echo "Claves ya existen para $HOST (usa --force para regenerar)"
  echo "  SSH: $PUB_FILE"
  echo "  WireGuard: $WG_PUB_FILE"
  echo ""
  echo "Sincronizando wireguard.json con clave existente..."

  WG_PUBLIC_KEY=$(cat "$WG_PUB_FILE")
  TIMESTAMP=$(date -Iseconds)
  TEMP_JSON=$(mktemp)

  if [ -f "$WG_STATE_FILE" ]; then
    $JQ_BIN --arg host "$HOST" \
      --arg pubkey "$WG_PUBLIC_KEY" \
      --arg timestamp "$TIMESTAMP" \
      '.[$host] = { "public_key": $pubkey, "generated_at": $timestamp }' \
      "$WG_STATE_FILE" >"$TEMP_JSON"
  else
    $JQ_BIN -n --arg host "$HOST" \
      --arg pubkey "$WG_PUBLIC_KEY" \
      --arg timestamp "$TIMESTAMP" \
      '{ ($host): { "public_key": $pubkey, "generated_at": $timestamp } }' \
      >"$TEMP_JSON"
  fi

  mv "$TEMP_JSON" "$WG_STATE_FILE"
  echo "wireguard.json actualizado para $HOST"
  echo ""
  echo "Clave pública WireGuard: $WG_PUBLIC_KEY"
  exit 0
fi

# Si llegamos aquí, necesitamos generar claves (o --force fue especificado)
if [ "$FORCE" = true ]; then
  echo "Regenerando claves (--force especificado)..."
fi

# =============================================================================
# PARTE 1: Generar claves SSH
# =============================================================================
echo "Generando claves SSH para $HOST..."

TEMP_KEY=$(mktemp)
$SSH_KEYGEN_BIN -t ed25519 -f "$TEMP_KEY" -N "" -C "root@$HOST" -q

cp "$TEMP_KEY.pub" "$PUB_FILE"
echo "Clave pública SSH guardada en: $PUB_FILE"

echo "Encriptando clave privada SSH con agenix..."
cd "$SECRETS_DIR"
cat "$TEMP_KEY" | $AGE_BIN -R <(echo "$ADMIN_SSH_KEY") -o "$AGE_FILE"

rm -f "$TEMP_KEY" "$TEMP_KEY.pub"

# =============================================================================
# PARTE 2: Generar claves WireGuard
# =============================================================================
echo ""
echo "Generando claves WireGuard para $HOST..."

TEMP_WG_KEY=$(mktemp)
TEMP_WG_PUB=$(mktemp)

# Generar clave privada y pública WireGuard
$WG_BIN genkey >"$TEMP_WG_KEY"
cat "$TEMP_WG_KEY" | $WG_BIN pubkey >"$TEMP_WG_PUB"

WG_PUBLIC_KEY=$(cat "$TEMP_WG_PUB")

# Guardar clave pública en archivo .pub
cp "$TEMP_WG_PUB" "$WG_PUB_FILE"
echo "Clave pública WireGuard guardada en: $WG_PUB_FILE"

# Encriptar clave privada WireGuard
echo "Encriptando clave privada WireGuard con agenix..."
cat "$TEMP_WG_KEY" | $AGE_BIN -R <(echo "$ADMIN_SSH_KEY") -o "$WG_AGE_FILE"
echo "Clave privada WireGuard encriptada en: $WG_AGE_FILE"

rm -f "$TEMP_WG_KEY" "$TEMP_WG_PUB"

# =============================================================================
# PARTE 3: Actualizar wireguard.json
# =============================================================================
echo ""
echo "Actualizando $WG_STATE_FILE..."

TIMESTAMP=$(date -Iseconds)
TEMP_JSON=$(mktemp)

# Usar jq para actualizar el JSON de forma atómica
if [ -f "$WG_STATE_FILE" ]; then
  $JQ_BIN --arg host "$HOST" \
    --arg pubkey "$WG_PUBLIC_KEY" \
    --arg timestamp "$TIMESTAMP" \
    '.[$host] = { "public_key": $pubkey, "generated_at": $timestamp }' \
    "$WG_STATE_FILE" >"$TEMP_JSON"
else
  # Crear nuevo archivo si no existe
  $JQ_BIN -n --arg host "$HOST" \
    --arg pubkey "$WG_PUBLIC_KEY" \
    --arg timestamp "$TIMESTAMP" \
    '{ ($host): { "public_key": $pubkey, "generated_at": $timestamp } }' \
    >"$TEMP_JSON"
fi

mv "$TEMP_JSON" "$WG_STATE_FILE"
echo "Estado WireGuard actualizado para $HOST"

# =============================================================================
# Resumen y rekey
# =============================================================================
echo ""
echo "Claves generadas para $HOST:"
echo "  SSH Pública: $PUB_FILE"
echo "  SSH Privada (encriptada): $AGE_FILE"
echo "  WireGuard Pública: $WG_PUB_FILE"
echo "  WireGuard Privada (encriptada): $WG_AGE_FILE"
echo ""
echo "Clave pública SSH:"
cat "$PUB_FILE"
echo ""
echo "Clave pública WireGuard:"
echo "$WG_PUBLIC_KEY"
echo ""

echo "Re-encriptando secretos para incluir las nuevas claves del host..."
cd "$SECRETS_DIR"
$SCRIPT_BIN -q -c "$AGENIX_BIN -r" /dev/null

echo ""
echo "Claves SSH y WireGuard generadas y secretos actualizados para $HOST"
