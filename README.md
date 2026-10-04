# nix-cc-on-the-web

Claude Code on the web 環境で nix をベースに環境を起動するための設定例

## Allowed Domains

Claude Code on the web の環境で追加すべきドメインの一覧。glob OK, 中間 glob NG (Ex. `nixos.*.org`)。[デフォルトリスト](https://code.claude.com/docs/en/cloud-environments#default-allowed-domains) は含む設定になっている前提。

```text
（追加不要）
```

Nix で使うホストはデフォルトリストに含まれているため、追加のドメインは不要。

| 用途 | ホスト | デフォルトリスト |
| --- | --- | --- |
| バイナリキャッシュ | `cache.nixos.org` | `*.nixos.org` |
| flake registry / nixpkgs チャンネル | `channels.nixos.org`, `releases.nixos.org` | `*.nixos.org` |
| Nix 本体のインストーラ（フォールバック時のみ） | `releases.nixos.org` | `*.nixos.org` |

デフォルトでブロックされることを確認したホスト（必要になったら追加する）:

- `*.cachix.org`: Cachix のバイナリキャッシュ（`nix-community.cachix.org` など）を使う場合
- `install.determinate.systems`: Determinate Nix Installer。セットアップスクリプトでは使っていない

### GitHub 上の flake input について

GitHub への通信は Allowed Domains ではなく GitHub プロキシを経由し、**セッションにアタッチされていないリポジトリへのアクセスは 403 になる**（`NixOS/nixpkgs` も対象）。そのため:

- `flake.lock` でロック済みの `github:` input は、`narHash` をもとに `cache.nixos.org` から substitute されるので取得できる（nixpkgs など公式キャッシュにあるもの）
- `nix flake update` / `nix flake lock` などで `github:` input を解決する操作（`api.github.com` を叩く）は失敗する。lock の更新はローカルで行う
- `nix run nixpkgs#foo` のような registry 経由の `nixpkgs` は `channels.nixos.org` に解決されるので使える

## セットアップスクリプト

Claude Code on the web の環境に設定すべきセットアップ処理

```bash
#!/usr/bin/env bash
#
# Claude Code on the web environment setup script (runs as root on Ubuntu 24.04).
# Paste this into the environment's "Setup script" field.

set -euo pipefail

log() {
  echo "[cloud-setup] $*" >&2
}

NIX_VERSION="2.34.6"
NIX_BIN="/nix/var/nix/profiles/default/bin"

# 1. Nix
# The default image ships Nix (nix-installer, flakes enabled), so this only runs as a fallback.
# GitHub release assets of unattached repos are blocked, so install from releases.nixos.org.
if [[ ! -x "$NIX_BIN/nix" ]]; then
  log "installing nix $NIX_VERSION"
  if ! command -v xz >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y -qq xz-utils
  fi
  installer="$(mktemp)"
  curl -fsSL "https://releases.nixos.org/nix/nix-$NIX_VERSION/install" -o "$installer"
  # No systemd in the VM, so install in single-user mode as root (no nixbld users)
  mkdir -p -m 0755 /nix /etc/nix
  cat >/etc/nix/nix.conf <<'EOF'
build-users-group =
extra-experimental-features = nix-command flakes
EOF
  sh "$installer" --no-daemon --yes --no-modify-profile
  rm -f "$installer"
  ln -sfn /root/.nix-profile /nix/var/nix/profiles/default
fi
export PATH="$NIX_BIN:$PATH"

# Agent proxy re-terminates TLS; the system bundle includes its CA
grep -q '^ssl-cert-file' /etc/nix/nix.conf /etc/nix/nix.custom.conf 2>/dev/null ||
  echo "ssl-cert-file = /etc/ssl/certs/ca-certificates.crt" >>/etc/nix/nix.conf

nix --version

# 2. direnv
# `nixpkgs` in the global flake registry resolves to channels.nixos.org (not GitHub), so this works.
if ! command -v direnv >/dev/null 2>&1; then
  log "installing direnv"
  nix profile add nixpkgs#direnv 2>/dev/null || nix profile install nixpkgs#direnv
fi
direnv version

# Trust every .envrc under /home/user (where repositories are cloned) without `direnv allow`
mkdir -p /root/.config/direnv
cat >/root/.config/direnv/direnv.toml <<'EOF'
[global]
hide_env_diff = true
warn_timeout = "5m"

[whitelist]
prefix = ["/home/user"]
EOF

# 3. Warm the dev shells so the environment cache already has them in /nix/store
shopt -s nullglob
for envrc in /home/user/*/.envrc; do
  dir="$(dirname "$envrc")"
  log "warming direnv environment in $dir"
  (cd "$dir" && direnv exec . true) || log "failed to warm $dir (continuing)"
done

log "done"
```

やっていること:

1. Nix: デフォルトイメージには Nix（nix-installer 製、flakes 有効）が入っているので通常はスキップ。無い場合は `releases.nixos.org` の公式インストーラで single-user インストールする（VM に systemd が無いため）
2. direnv: `nix profile add nixpkgs#direnv` でインストールし、`/home/user` 配下の `.envrc` を `direnv allow` 無しで信頼するよう whitelist を設定
3. `/home/user/*/.envrc` の devShell を事前にビルドし、環境キャッシュ（ファイルシステムのスナップショット）に `/nix/store` を含める

セッション開始後は `.claude/hooks/load-direnv.sh`（SessionStart / CwdChanged hook）が `direnv export bash` の結果を `CLAUDE_ENV_FILE` に書き出し、Bash ツールに devShell の環境が反映される。
