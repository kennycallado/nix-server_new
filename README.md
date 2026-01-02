# Webslab Infrastructure

Infraestructura del servidor Webslab gestionada con **NixOS**, **k3s** y **WireGuard**.

## Requisitos

- **Nix** con _experimental features_ (`flakes`, `nix-command`).
- Acceso SSH `root` al servidor destino (para instalación inicial).
- Clave SSH `~/.ssh/id_ed25519` configurada como administrador.

## 🚀 Bootstrap (Instalación Inicial)

Para añadir un nuevo nodo (ej: `agent_03`):

1.  **Configuración**: Crear `hosts/nodes/agent_03/config.nix`.
2.  **Generar Claves**:
    ```bash
    nix run .#keygen -- agent_03
    ```
3.  **Registrar Clave Pública**:
    - Copiar clave pública generada en `secrets/hosts/agent_03.pub`.
    - Añadirla a `secrets/secrets.nix`.
4.  **Actualizar Secretos**:
    ```bash
    nix run .#rekey
    ```
5.  **Instalar NixOS**:
    ```bash
    nix run .#install -- agent_03 <IP_PUBLICA>
    ```

## 🔄 Despliegue (Actualizaciones)

Para aplicar cambios en nodos existentes:

```bash
# Un solo nodo
deploy .#server_01

# Todo el cluster
deploy
```

## 🔐 Gestión de Secretos

### Sistema (Agenix)

Secretos de infraestructura (claves WireGuard, passwords de usuario).
Configurados en `secrets/secrets.nix`.

```bash
# Regenerar tras cambios en claves SSH o secrets.nix
nix run .#rekey
```

### Kubernetes (Sealed Secrets)

Secretos de aplicaciones (DB passwords, tokens).
Almacenados de forma segura en `modules/services/k3s/sealedsecrets/`.

```bash
# 1. Crear secreto localmente (dry-run)
kubectl create secret generic my-secret --from-literal=pass=1234 --dry-run=client -o yaml > secret.yaml

# 2. Sellar secreto (cifrar)
nix run .#seal -- secret.yaml modules/services/k3s/sealedsecrets/my-secret.yaml

# 3. Borrar secreto original y comitear el sellado
rm secret.yaml
git add modules/services/k3s/sealedsecrets/my-secret.yaml
```

## 🌐 Acceso al Cluster

El acceso a la API de Kubernetes está restringido a la VPN WireGuard.

1.  **Configurar WireGuard**: Asegúrate de estar conectado a la VPN.
2.  **Kubeconfig**:
    ```bash
    ssh admin@<IP_SERVER> "sudo cat /etc/rancher/k3s/k3s.yaml" | \
      sed 's/127.0.0.1/<IP_WIREGUARD_SERVER>/' > ~/.kube/config-webslab
    ```
3.  **Uso**:
    ```bash
    export KUBECONFIG=~/.kube/config-webslab
    kubectl get nodes
    ```

