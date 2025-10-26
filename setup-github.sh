#!/usr/bin/env bash
set -euo pipefail

# Usage: ./deploy_github_key.sh ubuntu@1.2.3.4 /path/to/aws.pem

if [ $# -ne 2 ]; then
  echo "Usage: $0 <ec2-user@ip> <path-to-pem>"
  exit 1
fi

EC2_HOST=$1
PEM_FILE=$2
LOCAL_KEY_PATH="$HOME/.ssh/github"
REMOTE_KEY_PATH="~/.ssh/github"

# Check for key
if [ ! -f "$LOCAL_KEY_PATH" ]; then
  echo "Error: $LOCAL_KEY_PATH does not exist."
  exit 1
fi

echo "Ensuring correct permissions on $PEM_FILE..."
chmod 400 "$PEM_FILE"

echo "Copying GitHub key to $EC2_HOST..."

# Ensure .ssh exists remotely
ssh -i "$PEM_FILE" -o StrictHostKeyChecking=no "$EC2_HOST" "mkdir -p ~/.ssh && chmod 700 ~/.ssh"

# Copy the key
scp -i "$PEM_FILE" -o StrictHostKeyChecking=no "$LOCAL_KEY_PATH" "$EC2_HOST:$REMOTE_KEY_PATH"

# Set permissions and SSH config remotely
ssh -i "$PEM_FILE" -o StrictHostKeyChecking=no "$EC2_HOST" <<'EOF'
chmod 600 ~/.ssh/github

# Add GitHub config if not present
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

echo "GitHub key deployed and configured on $EC2_HOST."
