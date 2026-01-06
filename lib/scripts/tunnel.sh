#!/usr/bin/env bash
set -euo pipefail

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Configuración del servidor
SERVER_IP="46.224.186.182"
SSH_USER="admin"

# Función para mostrar uso
show_usage() {
  echo ""
  echo -e "${CYAN}Uso:${NC} nix run .#tunnel [-- servicio]"
  echo ""
  echo -e "${CYAN}Servicios disponibles:${NC}"
  echo ""
  echo -e "  ${GREEN}all${NC}         Todos los servicios (default)"
  echo -e "  ${GREEN}argocd${NC}      Solo ArgoCD UI (puerto 8080)"
  echo -e "  ${GREEN}windmill${NC}    Solo Windmill UI (puerto 8000)"
  echo -e "  ${GREEN}grafana${NC}     Solo Grafana UI (puerto 3000)"
  echo -e "  ${GREEN}garage${NC}      Solo Garage WebUI (puerto 32009)"
  echo ""
  echo -e "${CYAN}Ejemplos:${NC}"
  echo "  nix run .#tunnel                    # Todos los servicios"
  echo "  nix run .#tunnel -- argocd          # Solo ArgoCD"
  echo "  nix run .#tunnel -- grafana         # Solo Grafana"
  echo ""
}

# Cleanup function para matar procesos en background
cleanup() {
  echo ""
  echo -e "${YELLOW}Cerrando túneles...${NC}"
  jobs -p | xargs -r kill 2>/dev/null || true
  exit 0
}

trap cleanup SIGINT SIGTERM

# Obtener credenciales del cluster
get_credentials() {
  echo -e "${CYAN}Obteniendo credenciales...${NC}"
  echo ""

  # ArgoCD
  ARGOCD_USER="admin"
  ARGOCD_PASS=$(ssh "${SSH_USER}@${SERVER_IP}" "sudo kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d" 2>/dev/null || echo "N/A")

  # Windmill superadmin (del SealedSecret)
  WINDMILL_USER=$(ssh "${SSH_USER}@${SERVER_IP}" "sudo kubectl -n windmill get secret windmill-superadmin -o jsonpath='{.data.email}' 2>/dev/null | base64 -d" 2>/dev/null || echo "admin@windmill.dev")
  WINDMILL_PASS=$(ssh "${SSH_USER}@${SERVER_IP}" "sudo kubectl -n windmill get secret windmill-superadmin -o jsonpath='{.data.password}' 2>/dev/null | base64 -d" 2>/dev/null || echo "changeme")

  # Grafana (from SealedSecret grafana-admin)
  GRAFANA_USER=$(ssh "${SSH_USER}@${SERVER_IP}" "sudo kubectl -n metrics get secret grafana-admin -o jsonpath='{.data.admin-user}' 2>/dev/null | base64 -d" 2>/dev/null || echo "admin")
  GRAFANA_PASS=$(ssh "${SSH_USER}@${SERVER_IP}" "sudo kubectl -n metrics get secret grafana-admin -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d" 2>/dev/null || echo "N/A")

  # Garage WebUI (del SealedSecret, formato user:bcrypt_hash - solo mostramos el user)
  GARAGE_AUTH=$(ssh "${SSH_USER}@${SERVER_IP}" "sudo kubectl -n garage get secret garage-webui-auth -o jsonpath='{.data.AUTH_USER_PASS}' 2>/dev/null | base64 -d" 2>/dev/null || echo "N/A")
  GARAGE_USER=$(echo "$GARAGE_AUTH" | cut -d: -f1 2>/dev/null || echo "N/A")
  GARAGE_PASS="${DIM}(hash bcrypt en secret)${NC}"

  # PostgreSQL superuser
  PG_USER=$(ssh "${SSH_USER}@${SERVER_IP}" "sudo kubectl -n postgres get secret postgresql-superuser -o jsonpath='{.data.username}' 2>/dev/null | base64 -d" 2>/dev/null || echo "N/A")
  PG_PASS=$(ssh "${SSH_USER}@${SERVER_IP}" "sudo kubectl -n postgres get secret postgresql-superuser -o jsonpath='{.data.password}' 2>/dev/null | base64 -d" 2>/dev/null || echo "N/A")
}

# Mostrar credenciales
print_credentials() {
  echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}                        CREDENCIALES                           ${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "  ${GREEN}ArgoCD${NC}        http://localhost:8080"
  echo -e "                User: ${ARGOCD_USER}"
  echo -e "                Pass: ${ARGOCD_PASS}"
  echo ""
  echo -e "  ${GREEN}Windmill${NC}      http://localhost:8000"
  echo -e "                User: ${WINDMILL_USER}"
  echo -e "                Pass: ${WINDMILL_PASS}"
  echo ""
  echo -e "  ${GREEN}Grafana${NC}       http://localhost:3000"
  echo -e "                User: ${GRAFANA_USER}"
  echo -e "                Pass: ${GRAFANA_PASS}"
  echo ""
  echo -e "  ${GREEN}Garage WebUI${NC}  http://localhost:32009"
  echo -e "                User: ${GARAGE_USER}"
  echo -e "                Pass: ${GARAGE_PASS}"
  echo ""
  echo -e "  ${GREEN}PostgreSQL${NC}    ${DIM}(interno: postgresql-rw.postgres.svc:5432)${NC}"
  echo -e "                User: ${PG_USER}"
  echo -e "                Pass: ${PG_PASS}"
  echo ""
  echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
  echo ""
}

# Túnel para todos los servicios
tunnel_all() {
  echo -e "${BLUE}Conectando a ${SSH_USER}@${SERVER_IP}...${NC}"
  echo ""
  
  get_credentials
  print_credentials

  echo -e "${YELLOW}Presiona Ctrl+C para cerrar todos los túneles${NC}"
  echo ""

  # Iniciar port-forwards en el servidor remoto
  ssh "${SSH_USER}@${SERVER_IP}" "sudo kubectl port-forward -n argocd svc/argocd-server 18080:80 --address 127.0.0.1 >/dev/null 2>&1" &
  ssh "${SSH_USER}@${SERVER_IP}" "sudo kubectl port-forward -n windmill svc/windmill-app 18000:8000 --address 127.0.0.1 >/dev/null 2>&1" &
  ssh "${SSH_USER}@${SERVER_IP}" "sudo kubectl port-forward -n metrics svc/kube-prometheus-stack-grafana 13000:80 --address 127.0.0.1 >/dev/null 2>&1" &
  
  sleep 2

  # Crear túnel SSH con todos los puertos
  ssh -N \
    -L 8080:localhost:18080 \
    -L 8000:localhost:18000 \
    -L 3000:localhost:13000 \
    -L 32009:localhost:32009 \
    "${SSH_USER}@${SERVER_IP}"
}

# Túnel solo para ArgoCD
tunnel_argocd() {
  echo -e "${BLUE}Conectando a ${SSH_USER}@${SERVER_IP}...${NC}"
  echo ""
  
  ARGOCD_USER="admin"
  ARGOCD_PASS=$(ssh "${SSH_USER}@${SERVER_IP}" "sudo kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d" 2>/dev/null || echo "N/A")
  
  echo -e "  ${GREEN}ArgoCD${NC}  http://localhost:8080"
  echo -e "          User: ${ARGOCD_USER}"
  echo -e "          Pass: ${ARGOCD_PASS}"
  echo ""
  echo -e "${YELLOW}Presiona Ctrl+C para cerrar${NC}"
  echo ""

  ssh "${SSH_USER}@${SERVER_IP}" "sudo kubectl port-forward -n argocd svc/argocd-server 18080:80 --address 127.0.0.1 >/dev/null 2>&1" &
  sleep 2
  ssh -N -L 8080:localhost:18080 "${SSH_USER}@${SERVER_IP}"
}

# Túnel solo para Windmill
tunnel_windmill() {
  echo -e "${BLUE}Conectando a ${SSH_USER}@${SERVER_IP}...${NC}"
  echo ""
  
  WINDMILL_USER=$(ssh "${SSH_USER}@${SERVER_IP}" "sudo kubectl -n windmill get secret windmill-superadmin -o jsonpath='{.data.email}' 2>/dev/null | base64 -d" 2>/dev/null || echo "admin@windmill.dev")
  WINDMILL_PASS=$(ssh "${SSH_USER}@${SERVER_IP}" "sudo kubectl -n windmill get secret windmill-superadmin -o jsonpath='{.data.password}' 2>/dev/null | base64 -d" 2>/dev/null || echo "changeme")
  
  echo -e "  ${GREEN}Windmill${NC}  http://localhost:8000"
  echo -e "            User: ${WINDMILL_USER}"
  echo -e "            Pass: ${WINDMILL_PASS}"
  echo ""
  echo -e "${YELLOW}Presiona Ctrl+C para cerrar${NC}"
  echo ""

  ssh "${SSH_USER}@${SERVER_IP}" "sudo kubectl port-forward -n windmill svc/windmill-app 18000:8000 --address 127.0.0.1 >/dev/null 2>&1" &
  sleep 2
  ssh -N -L 8000:localhost:18000 "${SSH_USER}@${SERVER_IP}"
}

# Túnel solo para Garage WebUI (NodePort directo)
tunnel_garage() {
  echo -e "${BLUE}Conectando a ${SSH_USER}@${SERVER_IP}...${NC}"
  echo ""
  
  GARAGE_AUTH=$(ssh "${SSH_USER}@${SERVER_IP}" "sudo kubectl -n garage get secret garage-webui-auth -o jsonpath='{.data.AUTH_USER_PASS}' 2>/dev/null | base64 -d" 2>/dev/null || echo "N/A")
  GARAGE_USER=$(echo "$GARAGE_AUTH" | cut -d: -f1 2>/dev/null || echo "N/A")
  
  echo -e "  ${GREEN}Garage${NC}  http://localhost:32009"
  echo -e "          User: ${GARAGE_USER}"
  echo -e "          Pass: ${DIM}(hash bcrypt en secret)${NC}"
  echo ""
  echo -e "${YELLOW}Presiona Ctrl+C para cerrar${NC}"
  echo ""

  ssh -N -L 32009:localhost:32009 "${SSH_USER}@${SERVER_IP}"
}

# Túnel solo para Grafana
tunnel_grafana() {
  echo -e "${BLUE}Conectando a ${SSH_USER}@${SERVER_IP}...${NC}"
  echo ""
  
  GRAFANA_USER=$(ssh "${SSH_USER}@${SERVER_IP}" "sudo kubectl -n metrics get secret grafana-admin -o jsonpath='{.data.admin-user}' 2>/dev/null | base64 -d" 2>/dev/null || echo "admin")
  GRAFANA_PASS=$(ssh "${SSH_USER}@${SERVER_IP}" "sudo kubectl -n metrics get secret grafana-admin -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d" 2>/dev/null || echo "N/A")
  
  echo -e "  ${GREEN}Grafana${NC}  http://localhost:3000"
  echo -e "           User: ${GRAFANA_USER}"
  echo -e "           Pass: ${GRAFANA_PASS}"
  echo ""
  echo -e "${YELLOW}Presiona Ctrl+C para cerrar${NC}"
  echo ""

  ssh "${SSH_USER}@${SERVER_IP}" "sudo kubectl port-forward -n metrics svc/kube-prometheus-stack-grafana 13000:80 --address 127.0.0.1 >/dev/null 2>&1" &
  sleep 2
  ssh -N -L 3000:localhost:13000 "${SSH_USER}@${SERVER_IP}"
}

# Main
SERVICE="${1:-all}"

case "$SERVICE" in
  all)
    tunnel_all
    ;;
  argocd)
    tunnel_argocd
    ;;
  windmill)
    tunnel_windmill
    ;;
  grafana)
    tunnel_grafana
    ;;
  garage)
    tunnel_garage
    ;;
  -h|--help|help)
    show_usage
    ;;
  *)
    echo -e "${RED}Servicio desconocido: $SERVICE${NC}"
    show_usage
    exit 1
    ;;
esac
