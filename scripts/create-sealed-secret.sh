#!/bin/bash
set -e

# Script to create a Sealed Secret for Factorio game password

NAMESPACE="factorio"
SECRET_NAME="factorio-game-password"
SECRET_KEY="game-password"
OUTPUT_FILE="k8s/config/sealed-secret.yaml"

echo "=== Factorio Game Password - Sealed Secret Generator ==="
echo

# Check if kubeseal is installed
if ! command -v kubeseal &> /dev/null; then
    echo "Error: kubeseal is not installed"
    echo "Install it with: brew install kubeseal (macOS) or see https://github.com/bitnami-labs/sealed-secrets"
    exit 1
fi

# Get password
if [ -n "$1" ]; then
    PASSWORD="$1"
    echo "Using password from command line argument"
else
    echo "Enter the game password (will not be displayed):"
    read -s PASSWORD
    echo
fi

if [ -z "$PASSWORD" ]; then
    echo "Error: Password cannot be empty"
    exit 1
fi

echo "Encrypting password..."

# Encrypt the password
ENCRYPTED=$(echo -n "$PASSWORD" | kubeseal --raw \
    --from-file=/dev/stdin \
    --name "$SECRET_NAME" \
    --namespace "$NAMESPACE")

if [ -z "$ENCRYPTED" ]; then
    echo "Error: Failed to encrypt password"
    exit 1
fi

# Create the sealed secret file
cat > "$OUTPUT_FILE" <<EOF
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: $SECRET_NAME
  namespace: $NAMESPACE
spec:
  encryptedData:
    $SECRET_KEY: $ENCRYPTED
  template:
    metadata:
      name: $SECRET_NAME
      namespace: $NAMESPACE
    type: Opaque
EOF

echo "✓ Sealed secret created: $OUTPUT_FILE"
echo
echo "Next steps:"
echo "  1. Review the file: cat $OUTPUT_FILE"
echo "  2. Commit: git add $OUTPUT_FILE && git commit -m 'Add game password'"
echo "  3. Push: git push"
echo
echo "The sealed secret is encrypted and safe to commit to the public repository."
