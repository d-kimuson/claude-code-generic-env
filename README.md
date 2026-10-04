# nix-cc-on-the-web

Claude Code on the web 環境で nix をベースに環境を起動するための設定例

## Allowed Domains

Claude Code on the web の環境で追加すべきドメインの一覧。glob OK, 中間 glob NG (Ex. `nixos.*.org`)。[デフォルトリスト](https://code.claude.com/docs/en/cloud-environments#default-allowed-domains) は含む設定になっている前提。

```text
example.com
*.example.com ※ format サンプルとして一旦置いてるので初期化時に消してください
```

## セットアップスクリプト

Claude Code on the web の環境に設定すべきセットアップ処理

```bash
#!/usr/bin/env bash

# TBD
```
