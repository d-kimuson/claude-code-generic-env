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
- GitHub は Allowed Domains の対象外（`github.com` 等はデフォルトリストに入っているが、それでも GitHub プロキシの制限を受ける）なので、ドメイン追加では回避できない
- 一方 git プロトコル経由の clone は通るので、cloud 上で lock を解決したい input は `git+https://github.com/NixOS/nixpkgs?ref=nixpkgs-unstable&shallow=1` のように書けば取得できる

## セットアップスクリプト

Claude Code on the web の環境に設定すべきセットアップ処理

```bash
#!/usr/bin/env bash

set -euo pipefail

# Nix はデフォルトイメージに導入済み (flakes 有効)
nix profile add nixpkgs#direnv

# /home/user 配下の .envrc を `direnv allow` 無しで信頼する
mkdir -p ~/.config/direnv
cat >~/.config/direnv/direnv.toml <<'EOF'
[whitelist]
prefix = ["/home/user"]
EOF

# devShell を事前ビルドして環境キャッシュに含める
shopt -s nullglob
for envrc in /home/user/*/.envrc; do
  direnv exec "$(dirname "$envrc")" true
done
```

やっていること:

1. direnv を `nix profile add nixpkgs#direnv` でインストール（registry の `nixpkgs` は `channels.nixos.org` に解決されるので GitHub 制限の影響を受けない）
2. `/home/user` 配下の `.envrc` を `direnv allow` 無しで信頼するよう whitelist を設定
3. `/home/user/*/.envrc` の devShell を事前にビルドし、環境キャッシュ（ファイルシステムのスナップショット）に `/nix/store` を含める

セッション開始後は `.claude/hooks/load-direnv.sh`（SessionStart / CwdChanged hook）が `direnv export bash` の結果を `CLAUDE_ENV_FILE` に書き出し、Bash ツールに devShell の環境が反映される。
