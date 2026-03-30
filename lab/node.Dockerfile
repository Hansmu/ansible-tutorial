FROM python:3.14.3-slim

RUN apt-get update && apt-get install -y \
    openssh-server \
    sudo \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# Create the SSH runtime directory and configure the daemon
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#AuthorizedKeysFile/AuthorizedKeysFile/' /etc/ssh/sshd_config

# Entrypoint: wait for shared SSH public key, install it, start sshd
COPY entrypoint-node.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]
