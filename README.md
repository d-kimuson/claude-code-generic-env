# claude-code-generic-env

Claude Code on the web で使う汎用環境の設定。Nix + direnv で各リポジトリの devShell を読み込み、必要に応じて mise（`mise.toml` や `.node-version` などのバージョンファイル）でランタイムを入れた状態でセッションを開始する。

## Allowed Domains

Claude Code on the web の環境で追加すべきドメインの一覧。glob OK, 中間 glob NG (Ex. `nixos.*.org`)。[デフォルトリスト](https://code.claude.com/docs/en/cloud-environments#default-allowed-domains) は含む設定になっている前提。

```text
*.cachix.org
*.jdx.dev
go.dev
dl.google.com
download.java.net
cache.ruby-lang.org
```

| ドメイン | 用途 |
| --- | --- |
| `*.jdx.dev` | mise: バージョン一覧・Java のメタデータ取得 |
| `dl.google.com` | mise: Go のダウンロード（`go.dev` からのリダイレクト先） |

## セットアップスクリプト

Claude Code on the web の環境に設定すべきセットアップ処理

```bash
#!/usr/bin/env bash

set -euo pipefail

# Nix is preinstalled in the default image (flakes enabled)
nix profile add nixpkgs#direnv

# Trust .envrc under /home/user without `direnv allow`
mkdir -p ~/.config/direnv
cat >~/.config/direnv/direnv.toml <<'EOF'
[whitelist]
prefix = ["/home/user"]
EOF

# Prebuild devShells so they are included in the environment cache
shopt -s nullglob
for envrc in /home/user/*/.envrc; do
  direnv exec "$(dirname "$envrc")" true
done

# Install runtimes with mise only for repositories that have version files
declare -A idiomatic_tools=(
  [.node-version]=node [.nvmrc]=node [.python-version]=python
  [.ruby-version]=ruby [.go-version]=go [.java-version]=java
)
mise_dirs=()
for dir in /home/user/*/; do
  found=false
  for f in mise.toml .mise.toml .tool-versions "${!idiomatic_tools[@]}"; do
    [[ -e "$dir$f" ]] && found=true
  done
  $found && mise_dirs+=("$dir")
done

if ((${#mise_dirs[@]} > 0)); then
  nix profile add nixpkgs#mise
  mise settings add trusted_config_paths /home/user
  # Disabled because the GitHub API returns 403 and attestation verification fails
  mise settings set github_attestations false
  for dir in "${mise_dirs[@]}"; do
    for f in "${!idiomatic_tools[@]}"; do
      [[ -e "$dir$f" ]] && mise settings add idiomatic_version_file_enable_tools "${idiomatic_tools[$f]}"
    done
  done
  echo 'eval "$(mise activate bash --shims)"' >>~/.bashrc
  for dir in "${mise_dirs[@]}"; do
    (cd "$dir" && mise install --yes)
  done
fi
```

## 注意事項

- GitHub は Allowed Domains ではなく GitHub プロキシの制限を受け、セッションにアタッチしていないリポジトリ（`NixOS/nixpkgs` 含む）は API アクセスが 403 になる
  - `flake.lock` でロック済みの `github:` input は `cache.nixos.org` から取得できる
  - `nix flake update` などの `github:` input の解決は失敗する。lock の更新はローカルで行う
  - cloud 上で解決したい input は `git+https://github.com/NixOS/nixpkgs?ref=nixpkgs-unstable&shallow=1` のように書けば取得できる
