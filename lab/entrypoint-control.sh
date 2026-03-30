#!/bin/bash
set -e

KEY_FILE="/root/.ssh/id_rsa"

# Generate SSH keypair once (shared volume persists it across restarts)
if [ ! -f "$KEY_FILE" ]; then
  echo "[control] Generating SSH keypair..."
  mkdir -p /root/.ssh
  ssh-keygen -t rsa -b 4096 -f "$KEY_FILE" -N ""
  chmod 700 /root/.ssh
  chmod 600 "$KEY_FILE"
  chmod 644 "${KEY_FILE}.pub"
  echo "[control] SSH keypair generated."
else
  echo "[control] SSH keypair already exists, skipping generation."
fi

# Disable strict host key checking so playbooks don't prompt
cat > /root/.ssh/config <<EOF
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
chmod 600 /root/.ssh/config

echo "[control] Ready. Run playbooks with:"
echo "  docker exec -it ansible-control ansible-playbook /ansible/playbooks/<your-playbook>.yml"

exec "$@"
