#!/bin/bash
set -e

# Script to create a Sealed Secret for Factorio mod portal credentials

NAMESPACE="factorio"
SECRET_NAME="factorio-mod-credentials"
OUTPUT_FILE="k8s/config/sealed-secret-mod-credentials.yaml"

echo "=== Factorio Mod Portal Credentials - Sealed Secret Generator ==="
echo

# Check if kubeseal is installed
if ! command -v kubeseal &> /dev/null; then
    echo "Error: kubeseal is not installed"
    echo "Install it with: brew install kubeseal (macOS) or see https://github.com/bitnami-labs/sealed-secrets"
    exit 1
fi

# Get username
if [ -n "$1" ]; then
    USERNAME="$1"
    echo "Using username from command line argument: $USERNAME"
else
    echo "Enter your Factorio username:"
    read USERNAME
fi

if [ -z "$USERNAME" ]; then
    echo "Error: Username cannot be empty"
    exit 1
fi

# Get token
if [ -n "$2" ]; then
    TOKEN="$2"
    echo "Using token from command line argument"
else
    echo "Enter your Factorio token (from https://factorio.com/profile):"
    echo "(will not be displayed)"
    read -s TOKEN
    echo
fi

if [ -z "$TOKEN" ]; then
    echo "Error: Token cannot be empty"
    exit 1
fi

echo "Encrypting credentials..."

# Encrypt the username
ENCRYPTED_USERNAME=$(echo -n "$USERNAME" | kubeseal --raw \
    --from-file=/dev/stdin \
    --name "$SECRET_NAME" \
    --namespace "$NAMESPACE" \
    --scope cluster-wide)

if [ -z "$ENCRYPTED_USERNAME" ]; then
    echo "Error: Failed to encrypt username"
    exit 1
fi

# Encrypt the token
ENCRYPTED_TOKEN=$(echo -n "$TOKEN" | kubeseal --raw \
    --from-file=/dev/stdin \
    --name "$SECRET_NAME" \
    --namespace "$NAMESPACE" \
    --scope cluster-wide)

if [ -z "$ENCRYPTED_TOKEN" ]; then
    echo "Error: Failed to encrypt token"
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
    username: $ENCRYPTED_USERNAME
    token: $ENCRYPTED_TOKEN
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
echo "  2. Update kustomization.yaml to include this secret"
echo "  3. Update StatefulSet to use USERNAME and TOKEN env vars"
echo "  4. Commit: git add $OUTPUT_FILE && git commit -m 'Add mod portal credentials'"
echo "  5. Push: git push"
echo
echo "The sealed secret is encrypted and safe to commit to the public repository."
echo
echo "Get your token from: https://factorio.com/profile"
