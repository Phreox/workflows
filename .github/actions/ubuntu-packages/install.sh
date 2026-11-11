#!/usr/bin/env bash
set -euo pipefail

# GitHub's Azure mirror can fail independently of the public Ubuntu mirrors.
if [[ $(dpkg --print-architecture) == amd64 ]]; then
  sudo sed -i 's|mirror+file:/etc/apt/apt-mirrors.txt|https://archive.ubuntu.com/ubuntu|g; s|http://azure.archive.ubuntu.com/ubuntu|https://archive.ubuntu.com/ubuntu|g' /etc/apt/sources.list.d/ubuntu.sources
  repository=archive.ubuntu.com
else
  repository=ports.ubuntu.com
fi

if ! timeout 15 getent ahosts "$repository" > /dev/null; then
  echo "::warning::Runner DNS cannot resolve $repository; retrying with public DNS."
  interface=$(ip -o route show default | awk '{print $5; exit}')
  [[ -n "$interface" ]]
  sudo resolvectl dns "$interface" 1.1.1.1 8.8.8.8
  sudo resolvectl domain "$interface" '~.'
  sudo resolvectl flush-caches
  timeout 15 getent ahosts "$repository" > /dev/null
fi

# apt-get update normally succeeds even when its indexes could not be fetched.
options=(-o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30)
sudo apt-get "${options[@]}" -o APT::Update::Error-Mode=any update
read -r -a packages <<< "$PACKAGES"
sudo apt-get "${options[@]}" install -y --no-install-recommends "${packages[@]}"
