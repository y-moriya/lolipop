#!/usr/bin/env bash
# push_and_deploy.sh
# 
# コードを Git にプッシュし、自動でビルドの完了を待ってから
# Windowsホスト側にデプロイします。

set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "=== 1. Git Push ==="
git push origin main

echo "=== 2. Build & Deploy ==="
# Wait 3 seconds for GitHub Actions to register the push
sleep 3
./scripts/deploy_snapshot.sh
