# Webslab Infrastructure

Cluster K3s sobre NixOS con WireGuard, gestionado declarativamente.

## Requisitos

- Nix con flakes (`nix-command`, `flakes`)
- Clave SSH en `~/.ssh/id_ed25519`
- Servidor con acceso root (rescue mode o imagen limpia)

## Comandos

```bash
nix run .#<comando> -- [args]
```

| Comando           | Descripción                          |
| ----------------- | ------------------------------------ |
| `check`           | Valida formatting y configuraciones  |
| `keygen <host>`   | Genera claves SSH y WireGuard        |
| `install-minimal` | Instala NixOS base (Phase 1)         |
| `deploy <host>`   | Despliega configuración (Phase 2)    |
| `seal`            | Sella secretos para Kubernetes       |
| `agenix`          | CLI de agenix                        |

## Añadir un nuevo nodo

```bash
# 1. Crear config (copiar de uno existente)
cp -r hosts/nodes/agent-01 hosts/nodes/nuevo-nodo
# Editar config.nix: hostname, wireguard.ip, k3s.role, deploy.ip

# 2. Añadir a git (necesario para que flake lo detecte)
git add hosts/nodes/nuevo-nodo

# 3. Generar claves SSH y WireGuard
nix run .#keygen -- nuevo-nodo

# 4. Añadir claves a secrets/secrets.nix

# 5. Actualizar nodos existentes (nuevos peers WireGuard)
nix run .#deploy -- --all

# 6. Instalar NixOS en el nuevo nodo
nix run .#install-minimal -- nuevo-nodo
nix run .#deploy -- nuevo-nodo
```

## Despliegue

```bash
nix run .#deploy -- server-01    # Un nodo
nix run .#deploy -- --all        # Todos
```

## Secretos

**Sistema (agenix):** `secrets/*.age` - claves SSH, WireGuard, passwords.

**Kubernetes (sealed-secrets):** `modules/services/k3s/sealedsecrets/*.yaml`

```bash
kubectl create secret generic my-secret \
  --from-literal=key=value \
  --dry-run=client -o yaml | nix run .#seal -- - sealedsecrets/my-secret.yaml
```

## Acceso al cluster

Requiere conexión WireGuard activa.

```bash
ssh admin@server-01 "sudo cat /etc/rancher/k3s/k3s.yaml" | \
  sed 's/127.0.0.1/10.100.10.1/' > ~/.kube/config
kubectl get nodes
```
