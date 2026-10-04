# nix-cc-on-the-web

Claude Code on the web 環境で nix をベースに環境を起動するための設定例

## Allowed Domains

Claude Code on the web の環境で追加すべきドメインの一覧。glob OK, 中間 glob NG (Ex. `nixos.*.org`)。[デフォルトリスト](https://code.claude.com/docs/en/cloud-environments#default-allowed-domains) は含む設定になっている前提。

```text
（追加不要）
```

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

## 注意事項

- GitHub は Allowed Domains ではなく GitHub プロキシの制限を受け、セッションにアタッチしていないリポジトリ（`NixOS/nixpkgs` 含む）は API アクセスが 403 になる
  - `flake.lock` でロック済みの `github:` input は `cache.nixos.org` から取得できる
  - `nix flake update` などの `github:` input の解決は失敗する。lock の更新はローカルで行う
  - cloud 上で解決したい input は `git+https://github.com/NixOS/nixpkgs?ref=nixpkgs-unstable&shallow=1` のように書けば取得できる
- `*.cachix.org` はデフォルトでブロックされる。Cachix のキャッシュを使う場合は Allowed Domains に追加する
