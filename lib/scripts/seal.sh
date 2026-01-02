#!/usr/bin/env bash
# seal.sh - Seal Kubernetes secrets using kubeseal
#
# Usage:
#   nix run .#seal                     - Show help
#   nix run .#seal -- input.yaml       - Seal and output to stdout
#   nix run .#seal -- input.yaml out.yaml - Seal and save to file

set -euo pipefail

CERT_PATH="secrets/sealed-secrets-cert.pem"

show_help() {
    cat << EOF
Seal Kubernetes Secrets with Sealed Secrets

Usage:
  nix run .#seal                         Show this help
  nix run .#seal -- <input>              Seal secret and output to stdout
  nix run .#seal -- <input> <output>     Seal secret and save to file

Arguments:
  <input>   Path to Kubernetes Secret YAML file
  <output>  Path to save the SealedSecret YAML (optional)

Certificate: $CERT_PATH

Example:
  # Create a secret
  kubectl create secret generic my-secret \\
    --from-literal=password=mysecretpassword \\
    --dry-run=client -o yaml > secret.yaml

  # Seal it
  nix run .#seal -- secret.yaml modules/services/k3s/sealedsecrets/my-secret.yaml

Notes:
  - The certificate must exist at $CERT_PATH
  - Secrets are sealed for the namespace specified in the input YAML
  - SealedSecrets can only be decrypted by the cluster with the matching key
EOF
}

# Check if certificate exists
if [[ ! -f "$CERT_PATH" ]]; then
    echo "Error: Certificate not found at $CERT_PATH"
    echo "Make sure you're running this from the repository root."
    exit 1
fi

# Parse arguments
if [[ $# -eq 0 ]]; then
    show_help
    exit 0
fi

INPUT_FILE="$1"
OUTPUT_FILE="${2:-}"

# Validate input file
if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: Input file not found: $INPUT_FILE"
    exit 1
fi

# Run kubeseal
if [[ -n "$OUTPUT_FILE" ]]; then
    "$KUBESEAL_BIN" --cert "$CERT_PATH" --format yaml < "$INPUT_FILE" > "$OUTPUT_FILE"
    echo "Sealed secret saved to: $OUTPUT_FILE"
else
    "$KUBESEAL_BIN" --cert "$CERT_PATH" --format yaml < "$INPUT_FILE"
fi
