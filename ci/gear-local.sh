#!/bin/sh
# Validate the gear layout locally (what gear-hshc does on ALS, minus hasher):
# pack the tree per .gear/rules and build the SRPM.
# Usage: ci/gear-local.sh   (results land in ./out-gear/)
set -e
cd "$(dirname "$0")/.."
mkdir -p out-gear
chmod 777 out-gear
podman run --rm -i -v "$PWD":/work:Z -w /work registry.altlinux.org/alt/alt:p11 sh -eux - <<'EOF'
set -euo pipefail
apt-get update -qq
apt-get install -y -qq gear git rpm-build
useradd -m builder
cp -a /work /tmp/build
chown -R builder: /tmp/build
runuser -u builder -- sh -eux -c '
    cd /tmp/build
    git config --global user.email "hasherc-ci@altlinux.org"
    git config --global user.name "Builder"
    git add .
    gear --commit --rpmbuild -- rpmbuild -bs /tmp/build/dkms-ddcci.spec
'
srpm=$(find /tmp /home/builder -name "dkms-ddcci-*.src.rpm" -print -quit)
cp -v "$srpm" /work/out-gear/
EOF
echo; ls -la out-gear/
