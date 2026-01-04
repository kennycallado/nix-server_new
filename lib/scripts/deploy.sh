#!/usr/bin/env bash
# Despliega configuración NixOS a hosts usando deploy-rs con remote build
# Uso: deploy.sh <hostname> | --all
# Variables esperadas: JQ_BIN

set -e

HOST="${1:-}"

if [ -z "$HOST" ]; then
  echo "Uso: nix run .#deploy -- <hostname>"
  echo "      nix run .#deploy -- --all"
  echo ""
  echo "Ejemplos:"
  echo "  nix run .#deploy -- server-01    # Deploy a un host específico"
  echo "  nix run .#deploy -- --all        # Deploy a todos los hosts"
  echo ""
  echo "Nota: La compilación se realiza en el servidor remoto (remoteBuild=true)"
  exit 1
fi

PROJECT_ROOT="$(pwd)"
STATE_DIR="$PROJECT_ROOT/hosts/state"
NODES_FILE="$STATE_DIR/nodes.json"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}info${NC} $1"; }
log_success() { echo -e "${GREEN}ok${NC} $1"; }
log_warn() { echo -e "${YELLOW}warn${NC} $1"; }
log_error() { echo -e "${RED}error${NC} $1"; }

# =============================================================================
# Validar que existe nodes.json
# =============================================================================
if [ ! -f "$NODES_FILE" ]; then
  log_error "No existe $NODES_FILE"
  echo ""
  echo "Primero debes aprovisionar al menos un host:"
  echo "  nix run .#provision -- <hostname>"
  exit 1
fi

# =============================================================================
# Función para deployar un host
# =============================================================================
deploy_host() {
  local target_host="$1"

  # Validar que el host existe en nodes.json
  local host_data
  host_data=$($JQ_BIN -r ".[\"$target_host\"] // empty" "$NODES_FILE")

  if [ -z "$host_data" ]; then
    log_error "Host '$target_host' no encontrado en $NODES_FILE"
    echo ""
    echo "Hosts disponibles:"
    $JQ_BIN -r 'keys[]' "$NODES_FILE" 2>/dev/null | sed 's/^/  - /' || echo "  (ninguno)"
    return 1
  fi

  local host_ip
  host_ip=$($JQ_BIN -r ".[\"$target_host\"].public_ip // \"unknown\"" "$NODES_FILE")
  local host_status
  host_status=$($JQ_BIN -r ".[\"$target_host\"].status // \"unknown\"" "$NODES_FILE")

  echo ""
  echo "=========================================="
  log_info "Deploying $target_host"
  echo "=========================================="
  echo "  IP:     $host_ip"
  echo "  Status: $host_status"
  echo ""

  # Advertir si el host no está en estado 'running'
  if [ "$host_status" != "running" ]; then
    log_warn "El host tiene status '$host_status' (no 'running')"
    echo "  El deploy puede fallar si el host no está completamente provisionado."
    echo ""
  fi

  log_info "Iniciando deploy con remote build habilitado..."
  log_info "La compilación se realizará en el servidor remoto ($host_ip)"
  echo ""

  # Ejecutar deploy-rs
  if nix run nixpkgs#deploy-rs -- ".#$target_host"; then
    log_success "Deploy completado para $target_host"
    return 0
  else
    log_error "Deploy falló para $target_host"
    return 1
  fi
}

# =============================================================================
# Modo --all: deployar a todos los hosts
# =============================================================================
if [ "$HOST" = "--all" ]; then
  log_info "Deploy a todos los hosts..."

  # Obtener lista de hosts
  HOSTS=$($JQ_BIN -r 'keys[]' "$NODES_FILE" 2>/dev/null)

  if [ -z "$HOSTS" ]; then
    log_error "No hay hosts en $NODES_FILE"
    echo ""
    echo "Primero debes aprovisionar al menos un host:"
    echo "  nix run .#provision -- <hostname>"
    exit 1
  fi

  HOST_COUNT=$(echo "$HOSTS" | wc -l)
  log_info "Se encontraron $HOST_COUNT host(s)"

  FAILED_HOSTS=()
  SUCCESS_HOSTS=()

  for h in $HOSTS; do
    if deploy_host "$h"; then
      SUCCESS_HOSTS+=("$h")
    else
      FAILED_HOSTS+=("$h")
    fi
  done

  # Resumen final
  echo ""
  echo "=========================================="
  echo "RESUMEN DE DEPLOY"
  echo "=========================================="

  if [ ${#SUCCESS_HOSTS[@]} -gt 0 ]; then
    log_success "Exitosos (${#SUCCESS_HOSTS[@]}):"
    for h in "${SUCCESS_HOSTS[@]}"; do
      echo "    - $h"
    done
  fi

  if [ ${#FAILED_HOSTS[@]} -gt 0 ]; then
    log_error "Fallidos (${#FAILED_HOSTS[@]}):"
    for h in "${FAILED_HOSTS[@]}"; do
      echo "    - $h"
    done
    exit 1
  fi

  echo ""
  log_success "Todos los deploys completados exitosamente!"
  exit 0
fi

# =============================================================================
# Modo normal: deployar a un host específico
# =============================================================================
if deploy_host "$HOST"; then
  echo ""
  echo "=========================================="
  log_success "Deploy completado!"
  echo "=========================================="
  echo ""
  echo "Próximos pasos:"
  echo "  - Ver estado:  nix run .#status"
  echo "  - SSH:         ssh admin@\$($JQ_BIN -r '.[\"$HOST\"].public_ip' \"$NODES_FILE\")"
  echo ""
  exit 0
else
  exit 1
fi
