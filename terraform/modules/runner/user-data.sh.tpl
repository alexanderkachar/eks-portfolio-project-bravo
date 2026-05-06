#!/bin/bash
set -eux

dnf update -y
dnf install -y awscli docker git gzip jq libicu tar

# Amazon Linux 2023 does not currently ship ripgrep in the enabled repos.
# The observability image mirror script uses `rg` to discover rendered chart images.
RG_VERSION="14.1.1"
rg_tmp="$(mktemp -d)"
curl -fsSL \
  -o "$rg_tmp/ripgrep.tar.gz" \
  "https://github.com/BurntSushi/ripgrep/releases/download/$RG_VERSION/ripgrep-$RG_VERSION-x86_64-unknown-linux-musl.tar.gz"
tar -xzf "$rg_tmp/ripgrep.tar.gz" -C "$rg_tmp"
install -m 0755 "$rg_tmp"/ripgrep-"$RG_VERSION"-*/rg /usr/local/bin/rg
rm -rf "$rg_tmp"

systemctl enable --now docker
usermod -aG docker ec2-user

# kubectl is required by the deploy workflow after kubeconfig is generated.
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# Helm — the package-charts workflow needs `helm push` to ECR OCI.
curl -fsSL -o /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod +x /tmp/get_helm.sh
/tmp/get_helm.sh

# GitHub Actions runner binary.
mkdir -p /opt/actions-runner
cd /opt/actions-runner
curl -o runner.tar.gz -L \
  "https://github.com/actions/runner/releases/download/v${runner_version}/actions-runner-linux-x64-${runner_version}.tar.gz"
tar xzf runner.tar.gz
chown -R ec2-user:ec2-user /opt/actions-runner

echo '${runner_register_script_b64}' | base64 -d > /usr/local/bin/runner-register.sh
chmod 0755 /usr/local/bin/runner-register.sh

cat > /etc/systemd/system/actions-runner.service <<'UNIT'
[Unit]
Description=GitHub Actions Runner (ephemeral, self-reregistering)
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/actions-runner
ExecStartPre=/usr/local/bin/runner-register.sh register
ExecStart=/opt/actions-runner/run.sh
ExecStopPost=/usr/local/bin/runner-register.sh unregister
Restart=always
RestartSec=10
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now actions-runner
