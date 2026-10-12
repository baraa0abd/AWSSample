# Every CLI the Makefile needs, at pinned versions, for control machines that cannot run them
# natively (Windows) or should not drift (anyone). Use through ./toolbox.sh.
# Build context is ansible/ (for the requirements files):  docker build -f toolbox/Dockerfile ansible/
FROM python:3.13-slim

ARG TOFU_VERSION=1.13.0
ARG HELM_VERSION=3.19.0
ARG KUBECTL_VERSION=1.36.5
ARG SOPS_VERSION=3.13.3
ARG AGE_VERSION=1.3.2
ARG AZURE_CLI_VERSION=2.91.0

RUN apt-get update && apt-get install -y --no-install-recommends openssh-client git make curl jq \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; cd /tmp; \
    curl -fsSL "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_amd64.tar.gz" | tar -xz -C /usr/local/bin tofu; \
    curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" | tar -xz --strip-components=1 -C /usr/local/bin linux-amd64/helm; \
    curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl"; \
    curl -fsSL -o /usr/local/bin/sops "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.amd64"; \
    curl -fsSL "https://github.com/FiloSottile/age/releases/download/v${AGE_VERSION}/age-v${AGE_VERSION}-linux-amd64.tar.gz" | tar -xz --strip-components=1 -C /usr/local/bin age/age age/age-keygen; \
    chmod +x /usr/local/bin/*

COPY requirements.txt requirements.yml /tmp/
RUN pip install --no-cache-dir -r /tmp/requirements.txt "azure-cli==${AZURE_CLI_VERSION}" \
    && ansible-galaxy collection install -r /tmp/requirements.yml -p /usr/share/ansible/collections

# A repo bind-mounted from Windows is world-writable and has no file modes:
# Ansible would ignore ansible.cfg, git would refuse the repo, ssh would refuse the key.
ENV ANSIBLE_CONFIG=/repo/ansible/ansible.cfg
RUN git config --system --add safe.directory /repo \
    && printf '%s\n' '#!/bin/sh' \
       'if [ -d /ssh-host ]; then mkdir -p ~/.ssh && cp /ssh-host/id_* ~/.ssh/ 2>/dev/null && chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_*; fi' \
       'exec "$@"' > /usr/local/bin/entrypoint && chmod +x /usr/local/bin/entrypoint
WORKDIR /repo
ENTRYPOINT ["entrypoint"]
CMD ["bash"]
