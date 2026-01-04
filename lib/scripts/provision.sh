#!/usr/bin/env bash
# Orquestador de aprovisionamiento: crea servidor en Hetzner, actualiza estado, genera claves e instala NixOS
# Uso: provision.sh <hostname>
# Variables esperadas: HCLOUD_BIN, JQ_BIN, AGE_BIN
# Variables opcionales:
#   SKIP_GIT_COMMIT=1  - No hacer git commit al final (útil para testing)

set -e

HOST="${1:-}"

if [ -z "$HOST" ]; then
  echo "Uso: nix run .#provision -- <hostname>"
  echo "Ejemplo: nix run .#provision -- agent_03"
  echo ""
  echo "Prerequisitos:"
  echo "  1. Crear hosts/nodes/<hostname>/config.nix con la sección 'infra'"
  echo "  2. HCLOUD_TOKEN disponible (o secrets/hcloud-token.age)"
  exit 1
fi

PROJECT_ROOT="$(pwd)"
STATE_DIR="$PROJECT_ROOT/hosts/state"
NODES_FILE="$STATE_DIR/nodes.json"
WG_FILE="$STATE_DIR/wireguard.json"
CONFIG_DIR="$PROJECT_ROOT/hosts/nodes/$HOST"
CONFIG_FILE="$CONFIG_DIR/config.nix"
TOKEN_FILE="$PROJECT_ROOT/secrets/hcloud-token.age"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# =============================================================================
# PASO 0: Validaciones previas
# =============================================================================
log_info "Validando configuración para $HOST..."

if [ ! -f "$CONFIG_FILE" ]; then
  log_error "No existe $CONFIG_FILE"
  echo ""
  echo "Crea el archivo de configuración del nodo primero:"
  echo "  mkdir -p $CONFIG_DIR"
  echo "  # Copia y adapta un config.nix existente"
  exit 1
fi

# Verificar que el nodo NO existe ya en nodes.json
if [ -f "$NODES_FILE" ]; then
  EXISTING=$($JQ_BIN -r ".[\"$HOST\"] // empty" "$NODES_FILE")
  if [ -n "$EXISTING" ]; then
    EXISTING_IP=$($JQ_BIN -r ".[\"$HOST\"].public_ip // \"unknown\"" "$NODES_FILE")
    log_error "El nodo '$HOST' ya existe en $NODES_FILE (IP: $EXISTING_IP)"
    echo ""
    echo "Si quieres recrearlo:"
    echo "  1. Destruye el existente: nix run .#destroy -- $HOST"
    echo "  2. Vuelve a ejecutar provision"
    exit 1
  fi
fi

# =============================================================================
# PASO 1: Extraer configuración de infraestructura del config.nix
# =============================================================================
log_info "Leyendo especificaciones de infraestructura..."

# Usar nix eval para extraer los valores de forma segura
PROVIDER=$(nix eval --raw --file "$CONFIG_FILE" infra.provider 2>/dev/null || echo "")
TYPE=$(nix eval --raw --file "$CONFIG_FILE" infra.type 2>/dev/null || echo "")
LOCATION=$(nix eval --raw --file "$CONFIG_FILE" infra.location 2>/dev/null || echo "")
SYSTEM=$(nix eval --raw --file "$CONFIG_FILE" system 2>/dev/null || echo "")

if [ -z "$PROVIDER" ] || [ -z "$TYPE" ] || [ -z "$LOCATION" ]; then
  log_error "Configuración 'infra' incompleta en $CONFIG_FILE"
  echo ""
  echo "Asegúrate de que el config.nix tiene:"
  echo "  infra = {"
  echo "    provider = \"hetzner\";"
  echo "    type = \"cax11\";  # o cax21, cpx11, etc."
  echo "    location = \"fsn1\";  # o nbg1, hel1"
  echo "  };"
  exit 1
fi

log_success "Infra: provider=$PROVIDER, type=$TYPE, location=$LOCATION, system=$SYSTEM"

# Validar provider soportado
if [ "$PROVIDER" != "hetzner" ] && [ "$PROVIDER" != "manual" ]; then
  log_error "Provider '$PROVIDER' no soportado. Usa 'hetzner' o 'manual'"
  exit 1
fi

# Provider manual = solo actualizar estado, no crear servidor
if [ "$PROVIDER" = "manual" ]; then
  log_warn "Provider 'manual' seleccionado - no se creará servidor en la nube"
  echo ""
  read -p "Introduce la IP del servidor manual: " MANUAL_IP
  if [ -z "$MANUAL_IP" ]; then
    log_error "IP requerida para provider manual"
    exit 1
  fi
  SERVER_IP="$MANUAL_IP"
  SERVER_ID="manual"
else
  # =============================================================================
  # PASO 2: Obtener HCLOUD_TOKEN
  # =============================================================================
  if [ -n "$HCLOUD_TOKEN" ]; then
    log_info "Usando HCLOUD_TOKEN del entorno"
  elif [ -f "$TOKEN_FILE" ]; then
    log_info "Desencriptando token de Hetzner..."
    HCLOUD_TOKEN=$($AGE_BIN -d -i ~/.ssh/id_ed25519 "$TOKEN_FILE" 2>/dev/null || echo "")
    if [ -z "$HCLOUD_TOKEN" ]; then
      log_error "No se pudo desencriptar $TOKEN_FILE"
      echo "Verifica que tienes acceso a ~/.ssh/id_ed25519"
      exit 1
    fi
  else
    log_error "HCLOUD_TOKEN no disponible"
    echo ""
    echo "Opciones:"
    echo "  1. export HCLOUD_TOKEN='tu-token'"
    echo "  2. Crear secrets/hcloud-token.age"
    exit 1
  fi
  export HCLOUD_TOKEN

  # =============================================================================
  # PASO 3: Crear servidor en Hetzner
  # =============================================================================
  log_info "Creando servidor '$HOST' en Hetzner..."

  # Determinar imagen según arquitectura
  # Nota: Hetzner usa el mismo nombre para ambas arquitecturas, selecciona automáticamente
  case "$SYSTEM" in
  "aarch64-linux") IMAGE="debian-12" ;; # Hetzner selecciona ARM automáticamente
  "x86_64-linux") IMAGE="debian-12" ;;
  *)
    log_error "Sistema '$SYSTEM' no soportado"
    exit 1
    ;;
  esac

  log_info "Usando imagen base: $IMAGE (será reemplazada por NixOS)"

  # Crear el servidor (stderr va a /dev/null para evitar mensajes de progreso)
  CREATE_OUTPUT=$($HCLOUD_BIN server create \
    --name "$HOST" \
    --type "$TYPE" \
    --location "$LOCATION" \
    --image "$IMAGE" \
    --ssh-key admin \
    -o json 2>/dev/null) || {
    log_error "Fallo al crear servidor en Hetzner"
    # Reintentar sin -o json para ver el error real
    $HCLOUD_BIN server create --name "$HOST" --type "$TYPE" --location "$LOCATION" --image "$IMAGE" --ssh-key admin 2>&1 || true
    exit 1
  }

  # Extraer datos del servidor creado
  SERVER_ID=$(echo "$CREATE_OUTPUT" | $JQ_BIN -r '.server.id')
  SERVER_IP=$(echo "$CREATE_OUTPUT" | $JQ_BIN -r '.server.public_net.ipv4.ip')

  if [ -z "$SERVER_IP" ] || [ "$SERVER_IP" = "null" ]; then
    log_error "No se pudo obtener la IP del servidor"
    echo "Respuesta: $CREATE_OUTPUT"
    # Intentar limpiar
    $HCLOUD_BIN server delete "$HOST" --quiet 2>/dev/null || true
    exit 1
  fi

  log_success "Servidor creado: ID=$SERVER_ID, IP=$SERVER_IP"
fi

# =============================================================================
# PASO 4: Actualizar nodes.json
# =============================================================================
log_info "Actualizando $NODES_FILE..."

TIMESTAMP=$(date -Iseconds)
TEMP_JSON=$(mktemp)

if [ -f "$NODES_FILE" ]; then
  $JQ_BIN --arg host "$HOST" \
    --arg provider "$PROVIDER" \
    --arg provider_id "$SERVER_ID" \
    --arg ip "$SERVER_IP" \
    --arg type "$TYPE" \
    --arg location "$LOCATION" \
    --arg timestamp "$TIMESTAMP" \
    '.[$host] = {
            "provider": $provider,
            "provider_id": (if $provider_id == "manual" then null else ($provider_id | tonumber) end),
            "public_ip": $ip,
            "type": $type,
            "location": $location,
            "status": "provisioning",
            "created_at": $timestamp,
            "updated_at": $timestamp
          }' "$NODES_FILE" >"$TEMP_JSON"
else
  $JQ_BIN -n --arg host "$HOST" \
    --arg provider "$PROVIDER" \
    --arg provider_id "$SERVER_ID" \
    --arg ip "$SERVER_IP" \
    --arg type "$TYPE" \
    --arg location "$LOCATION" \
    --arg timestamp "$TIMESTAMP" \
    '{ ($host): {
               "provider": $provider,
               "provider_id": (if $provider_id == "manual" then null else ($provider_id | tonumber) end),
               "public_ip": $ip,
               "type": $type,
               "location": $location,
               "status": "provisioning",
               "created_at": $timestamp,
               "updated_at": $timestamp
             } }' >"$TEMP_JSON"
fi

mv "$TEMP_JSON" "$NODES_FILE"
log_success "Estado actualizado en nodes.json"

# =============================================================================
# PASO 5: Generar claves SSH y WireGuard
# =============================================================================
log_info "Generando claves para $HOST..."

# Llamar a keygen como subproceso
# Nota: keygen.sh ya maneja wireguard.json
if ! nix run .#keygen -- "$HOST"; then
  log_error "Fallo en keygen"
  # Marcar como fallido pero no borrar el servidor (el usuario puede reintentar)
  $JQ_BIN --arg host "$HOST" '.[$host].status = "keygen_failed"' "$NODES_FILE" >"$TEMP_JSON"
  mv "$TEMP_JSON" "$NODES_FILE"
  exit 1
fi

log_success "Claves generadas"

# =============================================================================
# PASO 6: Esperar a que el servidor esté listo
# =============================================================================
if [ "$PROVIDER" = "hetzner" ]; then
  log_info "Esperando a que el servidor esté accesible (puede tardar 1-2 minutos)..."

  for i in {1..30}; do
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "root@$SERVER_IP" exit 2>/dev/null; then
      log_success "Servidor accesible por SSH"
      break
    fi
    echo -n "."
    sleep 5
  done
  echo ""
fi

# =============================================================================
# PASO 7: Instalar NixOS
# =============================================================================
log_info "Instalando NixOS en $HOST..."

# install.sh ya lee la IP de nodes.json
if ! nix run .#install -- "$HOST"; then
  log_error "Fallo en instalación de NixOS"
  $JQ_BIN --arg host "$HOST" '.[$host].status = "install_failed"' "$NODES_FILE" >"$TEMP_JSON"
  mv "$TEMP_JSON" "$NODES_FILE"
  exit 1
fi

# =============================================================================
# PASO 8: Actualizar estado final y commit
# =============================================================================
log_info "Finalizando..."

$JQ_BIN --arg host "$HOST" --arg timestamp "$(date -Iseconds)" \
  '.[$host].status = "running" | .[$host].updated_at = $timestamp' \
  "$NODES_FILE" >"$TEMP_JSON"
mv "$TEMP_JSON" "$NODES_FILE"

# Git commit (skip with SKIP_GIT_COMMIT=1 for testing)
if [ "${SKIP_GIT_COMMIT:-}" = "1" ]; then
  log_warn "Skipping git commit (SKIP_GIT_COMMIT=1)"
else
  log_info "Committing cambios al repositorio..."
  git add "$STATE_DIR/"
  git add "$PROJECT_ROOT/secrets/" 2>/dev/null || true # Por si hay nuevos secrets
  git commit -m "provision: created $HOST ($TYPE @ $LOCATION, IP: $SERVER_IP)" || {
    log_warn "No hay cambios que commitear (o commit falló)"
  }
fi

# =============================================================================
# RESUMEN FINAL
# =============================================================================
echo ""
echo "=========================================="
log_success "Servidor '$HOST' aprovisionado exitosamente!"
echo "=========================================="
echo ""
echo "  Hostname:  $HOST"
echo "  Provider:  $PROVIDER"
echo "  Type:      $TYPE"
echo "  Location:  $LOCATION"
echo "  IP:        $SERVER_IP"
echo ""
echo "Próximos pasos:"
echo "  - Ver estado:     nix run .#status"
echo "  - Deploy config:  nix run nixpkgs#deploy-rs -- .#$HOST"
echo "  - SSH:            ssh admin@$SERVER_IP"
echo ""
