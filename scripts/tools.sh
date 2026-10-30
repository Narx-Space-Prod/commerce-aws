#!/usr/bin/env bash
# Pinned Linux amd64 tools; no curl-to-shell installation.
set -euo pipefail
destination="${RUNNER_TEMP:-$PWD/.work}/bin"
mkdir -p "$destination"
for tool in "$@"; do
  case "$tool" in
    actionlint)
      url=https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_amd64.tar.gz
      checksum=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8 ;;
    gitleaks)
      url=https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz
      checksum=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb ;;
    trivy)
      url=https://github.com/aquasecurity/trivy/releases/download/v0.76.1/trivy_0.76.1_Linux-64bit.tar.gz
      checksum=c7cbe3137fb8a48a17574bede3dd6beb16742d1e9772929940fc90082c39d9c0 ;;
    helm)
      url=https://get.helm.sh/helm-v3.22.0-linux-amd64.tar.gz
      checksum=1e4ab49e429626cf6c6958d914248b78c9730803c2751b87627e171dc800e7bb ;;
    kubeconform)
      url=https://github.com/yannh/kubeconform/releases/download/v0.8.0/kubeconform-linux-amd64.tar.gz
      checksum=9bc2bffbf71f261128533edaf912153948b7ff238f9a531ae6d34466ec287883 ;;
    *) echo "Unknown tool: $tool" >&2; exit 1 ;;
  esac
  archive=$(mktemp)
  curl --fail --silent --show-error --location --retry 2 --connect-timeout 10 --max-time 120 "$url" --output "$archive"
  printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check --strict
  if [ "$tool" = helm ]; then
    tar -xzf "$archive" -C "$destination" --strip-components=1 linux-amd64/helm
  else
    tar -xzf "$archive" -C "$destination" "$tool"
  fi
  rm -f "$archive"
done
if [ -n "${GITHUB_PATH:-}" ]; then printf '%s\n' "$destination" >> "$GITHUB_PATH"; fi
printf 'Tools installed in %s\n' "$destination"
