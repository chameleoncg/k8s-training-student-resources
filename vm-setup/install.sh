#!/bin/bash
set -eux

# Ubuntu 24.04
# set this to amd64 or arm64 based on your vm architecture
ARCH=amd64

export DEBIAN_FRONTEND=noninteractive

apt-get update -y

apt-get install -y \
  curl \
  ca-certificates \
  apt-transport-https \
  software-properties-common \
  git \
  make \
  docker.io \
  clang \
  curl\
  llvm \
  libelf-dev \
  gcc-multilib \
  linux-headers-$(uname -r) \
  libbpf-dev \
  tree \
  jq \
  wget

apt-get upgrade -y

# Cloud-init config (k8s-training user)
echo "==> Configuring cloud-init user..."

cat <<EOF > /etc/cloud/cloud.cfg.d/99-k8s-training-user.cfg
#cloud-config

system_info:
  default_user:
    name: k8s-training
    groups: [sudo, docker]
    shell: /bin/bash

users:
  - default

ssh_pwauth: false

runcmd:
  - [ systemctl, restart, docker ]
EOF

# Download Oras binary to usr/local/bin
ORAS_VERSION=1.3.1
curl -L "https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}/oras_${ORAS_VERSION}_linux_${ARCH}.tar.gz" | tar -zxf - oras
chmod +x ./oras
mv ./oras /usr/local/bin/oras

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install k9s
K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | jq -r .tag_name)
curl -L https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${ARCH}.tar.gz -o k9s.tar.gz
tar -xzf k9s.tar.gz
mv k9s /usr/local/bin/
chmod +x /usr/local/bin/k9s

# Install yq
YQ_VERSION=$(curl -s https://api.github.com/repos/mikefarah/yq/releases/latest | jq -r .tag_name)
wget https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${ARCH} -O /usr/local/bin/yq
chmod +x /usr/local/bin/yq

# Install RKE2
curl -sfL https://get.rke2.io | sh -
 
# Download Kind binary to usr/local/bin
KIND_VERSION=v0.31.0
curl -Lo ./kind https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${ARCH}
chmod +x ./kind
mv ./kind /usr/local/bin/kind

# Download Flux binary to usr/local/bin
curl -s https://fluxcd.io/install.sh | sudo bash

# Create a folder and add the lab scripts
mkdir -p "/etc/skel/scripts"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp -r "${SCRIPT_DIR}/custom-scripts/"* "/etc/skel/scripts/"
chown -R root:root /etc/skel/scripts
chmod -R 755 /etc/skel/scripts

# create custom commands that can be ran by students
cat << 'EOF' > /usr/local/bin/kind_up
#!/bin/bash
~/scripts/kind.sh -i "$@"
EOF

cat << 'EOF' > /usr/local/bin/kind_down
#!/bin/bash
~/scripts/kind.sh -s "$@"
EOF

cat << 'EOF' > /usr/local/bin/registry_up
#!/bin/bash
~/scripts/registry.sh -i "$@"
EOF

cat << 'EOF' > /usr/local/bin/registry_down
#!/bin/bash
~/scripts/registry.sh -s "$@"
EOF

chmod +x /usr/local/bin/kind_up \
         /usr/local/bin/kind_down \
         /usr/local/bin/registry_up \
         /usr/local/bin/registry_down

# Add Registry to etc/hosts
grep -qxF "127.0.0.1 lab.registry" /etc/hosts || echo "127.0.0.1 lab.registry" | tee -a /etc/hosts

#enable auto complete for flux, helm, kubectl
cat <<'EOF' > /etc/profile.d/k8s-completion.sh
#!/bin/bash
# K8s + Helm + Flux completion

if command -v kubectl >/dev/null 2>&1; then
  source <(kubectl completion bash)
  alias k=kubectl
  complete -F __start_kubectl k
fi

if command -v helm >/dev/null 2>&1; then
  source <(helm completion bash)
fi

if command -v flux >/dev/null 2>&1; then
  source <(flux completion bash)
fi
EOF

chmod +x /etc/profile.d/k8s-completion.sh
 
# Cleanup
apt-get clean