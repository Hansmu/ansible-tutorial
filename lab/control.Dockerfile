FROM python:3.14.3-slim

RUN apt-get update && apt-get install -y \
    openssh-client \
    sshpass \
    && pip install ansible \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /ansible

# Entrypoint: generate SSH keypair if not already present, then hand off
COPY entrypoint-control.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
