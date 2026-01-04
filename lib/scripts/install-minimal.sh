#!/usr/bin/env bash
# Instala la configuración minimal de NixOS usando nixos-anywhere (Fase 1)
# Uso: install-minimal.sh <hostname>
# Variables esperadas: AGE_BIN, NIXOS_ANYWHERE_BIN, JQ_BIN

set -e

HOST="${1:-}"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Verificar binarios requeridos
: "${AGE_BIN:?AGE_BIN not set}"
: "${NIXOS_ANYWHERE_BIN:?NIXOS_ANYWHERE_BIN not set}"
: "${JQ_BIN:?JQ_BIN not set}"

if [ -z "$HOST" ]; then
  echo "Uso: nix run .#install-minimal -- <hostname>"
  echo ""
  echo "Instala la configuración minimal (Fase 1) en un servidor remoto."
  echo "Esta configuración incluye solo lo básico: SSH, particionado y bootstrap."
  echo ""
  echo "Ejemplo: nix run .#install-minimal -- server-01"
  exit 1
fi

PROJECT_ROOT="$(pwd)"
SECRETS_DIR="$PROJECT_ROOT/secrets"
STATE_DIR="$PROJECT_ROOT/hosts/state"
NODES_FILE="$STATE_DIR/nodes.json"
AGE_FILE="$SECRETS_DIR/hosts/$HOST.age"
PUB_FILE="$SECRETS_DIR/hosts/$HOST.pub"

# =============================================================================
# Validar que el host existe en nodes.json
# =============================================================================
log_info "Validando configuración para '$HOST'..."

if [ ! -f "$NODES_FILE" ]; then
  log_error "No existe $NODES_FILE"
  echo ""
  echo "El archivo de estado no existe. Ejecuta primero:"
  echo "  nix run .#provision -- $HOST"
  exit 1
fi

IP=$($JQ_BIN -r ".[\"$HOST\"].public_ip // empty" "$NODES_FILE")

if [ -z "$IP" ]; then
  log_error "No se encontró '$HOST' en $NODES_FILE"
  echo ""
  echo "Nodos disponibles:"
  $JQ_BIN -r 'keys[]' "$NODES_FILE" 2>/dev/null | sed 's/^/  - /' || echo "  (ninguno)"
  echo ""
  echo "Opciones:"
  echo "  1. Verifica que el hostname es correcto"
  echo "  2. Añade el nodo: nix run .#provision -- $HOST"
  exit 1
fi

log_success "Host encontrado: $HOST ($IP)"

# =============================================================================
# Verificar que existen las claves SSH del host
# =============================================================================
log_info "Verificando claves SSH..."

if [ ! -f "$AGE_FILE" ]; then
  log_error "No existe la clave privada: $AGE_FILE"
  echo ""
  echo "Genera las claves primero:"
  echo "  nix run .#keygen -- $HOST"
  exit 1
fi

if [ ! -f "$PUB_FILE" ]; then
  log_error "No existe la clave pública: $PUB_FILE"
  echo ""
  echo "Genera las claves primero:"
  echo "  nix run .#keygen -- $HOST"
  exit 1
fi

log_success "Claves SSH encontradas"

# =============================================================================
# Preparar archivos extra (claves SSH para inyectar)
# =============================================================================
log_info "Preparando archivos para inyección..."

EXTRA_FILES=$(mktemp -d)
trap "rm -rf $EXTRA_FILES" EXIT

# Crear directorio SSH con permisos correctos
install -d -m700 "$EXTRA_FILES/etc/ssh"

# Desencriptar clave privada del host
log_info "Desencriptando clave SSH del host..."
if ! $AGE_BIN -d -i ~/.ssh/id_ed25519 "$AGE_FILE" >"$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key" 2>/dev/null; then
  log_error "No se pudo desencriptar $AGE_FILE"
  echo ""
  echo "Verifica que tienes acceso a ~/.ssh/id_ed25519"
  exit 1
fi
chmod 600 "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key"

# Copiar clave pública
cp "$PUB_FILE" "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key.pub"
chmod 644 "$EXTRA_FILES/etc/ssh/ssh_host_ed25519_key.pub"

log_success "Claves SSH preparadas para inyección"

# =============================================================================
# Ejecutar nixos-anywhere con configuración minimal
# =============================================================================
log_info "Instalando configuración minimal en $HOST ($IP)..."
echo ""
echo "  Flake:  .#$HOST-minimal"
echo "  Target: root@$IP"
echo ""

$NIXOS_ANYWHERE_BIN \
  --flake ".#$HOST-minimal" \
  --extra-files "$EXTRA_FILES" \
  "root@$IP"

# =============================================================================
# Finalización
# =============================================================================
echo ""
log_success "Instalación minimal completada!"
echo ""
echo "El servidor '$HOST' ahora tiene:"
echo "  - Particionado de disco configurado"
echo "  - Sistema base NixOS"
echo "  - Claves SSH del host instaladas"
echo "  - Acceso SSH habilitado"
echo ""
echo "Próximos pasos (Fase 2):"
echo "  - Instalar configuración completa: nix run .#install -- $HOST"
echo "  - O usar deploy-rs: nix run nixpkgs#deploy-rs -- .#$HOST"
echo ""
