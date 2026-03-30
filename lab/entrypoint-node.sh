#!/bin/bash
set -e

PUB_KEY="/tmp/ssh-keys/id_rsa.pub"
AUTH_KEYS="/root/.ssh/authorized_keys"

# Wait for the control node to generate the keypair on the shared volume
echo "[node] Waiting for SSH public key from control node..."
for i in $(seq 1 30); do
  if [ -f "$PUB_KEY" ]; then
    break
  fi
  echo "[node] Not ready yet, retrying in 2s... ($i/30)"
  sleep 2
done

if [ ! -f "$PUB_KEY" ]; then
  echo "[node] ERROR: SSH public key never appeared. Is the control node running?"
  exit 1
fi

# Install the control node's public key for root login
mkdir -p /root/.ssh
cp "$PUB_KEY" "$AUTH_KEYS"
chmod 700 /root/.ssh
chmod 600 "$AUTH_KEYS"

echo "[node] SSH public key installed. Starting sshd..."
exec /usr/sbin/sshd -D
