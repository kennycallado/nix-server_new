#!/usr/bin/env bash
# Re-encripta secretos con agenix
# Variables esperadas: AGENIX_BIN, SCRIPT_BIN

set -e
cd "$(pwd)/secrets"

echo "Re-encriptando secretos con agenix..."
$SCRIPT_BIN -q -c "$AGENIX_BIN -r" /dev/null
echo "Secretos re-encriptados."
