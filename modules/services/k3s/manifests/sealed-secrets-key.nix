# Sealed Secrets Key Bootstrap
#
# Este módulo genera un script que crea el Secret de Kubernetes con la clave
# de sellado ANTES de que el controller de Sealed Secrets arranque.
# Esto permite que el controller use nuestra clave persistente en lugar de
# generar una nueva, haciendo el sistema reproducible.
#
{ pkgs, lib ? pkgs.lib, sealedSecretsKeyPath, sealedSecretsCertPath }:

let
  # Script que genera el manifest con la clave en base64
  # Se ejecuta en tiempo de activación del sistema (después de agenix)
  generateManifest = pkgs.writeShellScript "generate-sealed-secrets-key-manifest" ''
    set -euo pipefail

    KEY_PATH="${sealedSecretsKeyPath}"
    CERT_PATH="${sealedSecretsCertPath}"
    OUTPUT_DIR="/var/lib/rancher/k3s/server/manifests"
    OUTPUT_PATH="$OUTPUT_DIR/00-sealed-secrets-key.yaml"

    # Verificar que los archivos fuente existen
    if [ ! -f "$KEY_PATH" ]; then
      echo "ERROR: Sealed secrets key not found at $KEY_PATH"
      exit 1
    fi

    if [ ! -f "$CERT_PATH" ]; then
      echo "ERROR: Sealed secrets cert not found at $CERT_PATH"
      exit 1
    fi

    # Crear directorio si no existe
    mkdir -p "$OUTPUT_DIR"

    # Base64 encode key and cert
    KEY_B64=$(${pkgs.coreutils}/bin/base64 -w0 < "$KEY_PATH")
    CERT_B64=$(${pkgs.coreutils}/bin/base64 -w0 < "$CERT_PATH")

    # Generar el manifest
    # Nota: El nombre empieza con "00-" para asegurar que se aplique antes
    # que el Helm chart de sealed-secrets (orden alfabético en k3s)
    cat > "$OUTPUT_PATH" << EOF
    apiVersion: v1
    kind: Secret
    metadata:
      name: sealed-secrets-key
      namespace: kube-system
      labels:
        sealedsecrets.bitnami.com/sealed-secrets-key: active
    type: kubernetes.io/tls
    data:
      tls.crt: $CERT_B64
      tls.key: $KEY_B64
    EOF

    # Asegurar permisos restrictivos
    chmod 600 "$OUTPUT_PATH"

    echo "[sealed-secrets-key] Manifest generated at $OUTPUT_PATH"
  '';

in
{
  inherit generateManifest;
}
