#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 'ssh -i <pem_file> <user@host>'"
  exit 1
fi

SSH_CMD="$*"

# Extract PEM file (the token after -i)
PEM_FILE=$(echo "$SSH_CMD" | awk '{for (i=1; i<=NF; i++) if ($i == "-i") print $(i+1)}' | tr -d '"')
if [ -z "$PEM_FILE" ]; then
  echo "Error: could not parse PEM file from command."
  exit 1
fi

# Extract host (last token in command)
EC2_HOST=$(echo "$SSH_CMD" | awk '{print $NF}')
if [ -z "$EC2_HOST" ]; then
  echo "Error: could not parse host from command."
  exit 1
fi

echo "[INFO] PEM file: $PEM_FILE"
echo "[INFO] EC2 host: $EC2_HOST"

# Deploy GitHub SSH key
LOCAL_KEY_PATH="$HOME/.ssh/github"
REMOTE_KEY_PATH="~/.ssh/github"

if [ ! -f "$LOCAL_KEY_PATH" ]; then
  echo "Error: $LOCAL_KEY_PATH does not exist."
  exit 1
fi

echo "[STEP] Setting PEM file permissions..."
chmod 400 "$PEM_FILE"

echo "[STEP] Ensuring ~/.ssh on remote..."
ssh -i "$PEM_FILE" -o StrictHostKeyChecking=no "$EC2_HOST" "mkdir -p ~/.ssh && chmod 700 ~/.ssh"

echo "[STEP] Copying GitHub key..."
scp -i "$PEM_FILE" -o StrictHostKeyChecking=no "$LOCAL_KEY_PATH" "$EC2_HOST:$REMOTE_KEY_PATH"

echo "[STEP] Configuring remote SSH for GitHub..."
ssh -i "$PEM_FILE" -o StrictHostKeyChecking=no "$EC2_HOST" <<'EOF'
chmod 600 ~/.ssh/github
if ! grep -q "Host github.com" ~/.ssh/config 2>/dev/null; then
  cat <<CONFIG >> ~/.ssh/config
Host github.com
  HostName github.com
  IdentityFile ~/.ssh/github
  StrictHostKeyChecking no
CONFIG
fi
eval "$(ssh-agent -s)" >/dev/null 2>&1
ssh-add ~/.ssh/github
EOF

echo "[DONE] GitHub key deployed and configured on $EC2_HOST"
