#!/usr/bin/env bash
# deploy_snapshot.sh
# 
# WSL上で実行し、GitHub Actions の最新ビルドを待ってから
# WindowsのホストWorkspaceに解凍コピーします。

set -e

# プロジェクトのルートディレクトリに移動
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

WINDOWS_WORKSPACE="/mnt/c/Users/wellk/workspace/anman-ai-test"
TEMP_DIR="/tmp/anman-ai-test-deploy"

echo "=== 1. GitHub Actions のビルド完了を待機しています ==="
# 直近のビルド実行を取得し、完了するまでブロック監視する
LATEST_RUN_ID=$(gh run list --workflow="release.yml" --limit 1 --json databaseId -q ".[0].databaseId")

if [ -z "$LATEST_RUN_ID" ]; then
  echo "Error: No GitHub Actions runs found for release.yml"
  exit 1
fi

echo "Latest Run ID: $LATEST_RUN_ID"
echo "Monitoring workflow execution... (Please wait)"
gh run watch "$LATEST_RUN_ID"

# 実行ステータスを確認
STATUS=$(gh run view "$LATEST_RUN_ID" --json conclusion -q ".conclusion")
if [ "$STATUS" != "success" ]; then
  echo "Error: GitHub Actions run $LATEST_RUN_ID ended with status: $STATUS"
  exit 1
fi
echo "GitHub Actions build completed successfully!"

echo "=== 2. Snapshot ZIP パッケージのダウンロード ==="
mkdir -p "$TEMP_DIR"
gh release download snapshot --pattern "*.zip" --dir "$TEMP_DIR" --clobber

echo "=== 3. パッケージの解凍 ==="
rm -rf "$TEMP_DIR/extracted"
mkdir -p "$TEMP_DIR/extracted"
unzip -o "$TEMP_DIR/anman-ai-snapshot-windows.zip" -d "$TEMP_DIR/extracted"

echo "=== 4. Windows ホスト Workspace への上書きコピー ==="
mkdir -p "$WINDOWS_WORKSPACE"
cp -r "$TEMP_DIR/extracted/anman-ai-snapshot-windows"/* "$WINDOWS_WORKSPACE/"

echo "=== 5. 設定ファイル (config.yaml) の復元・マージ ==="
BACKUP_CONFIG="$WINDOWS_WORKSPACE/config.yaml"
TARGET_CONFIG="$WINDOWS_WORKSPACE/config/config.yaml"

if [ -f "$BACKUP_CONFIG" ]; then
  echo "Found backup config.yaml at workspace root. Merging into config/config.yaml..."
  ruby -ryaml -rfileutils -e '
    backup_path = ARGV[0]
    target_path = ARGV[1]
    
    backup = YAML.load_file(backup_path) rescue nil
    target = YAML.load_file(target_path) rescue nil
    
    if backup && target
      def deep_merge(target_hash, source_hash)
        target_hash.merge(source_hash) do |key, oldval, newval|
          if oldval.is_a?(Hash) && newval.is_a?(Hash)
            deep_merge(oldval, newval)
          else
            newval
          end
        end
      end
      
      merged = deep_merge(target, backup)
      File.write(target_path, YAML.dump(merged))
      puts "Successfully merged backup config into config/config.yaml!"
    else
      puts "\e[31m[WARNING] config.yaml could not be merged (possibly due to format changes or invalid YAML syntax)!\e[0m"
      puts "\e[31mOverwriting config/config.yaml with raw backup file to preserve credentials.\e[0m"
      FileUtils.cp(backup_path, target_path) if File.exist?(backup_path)
    end
  ' "$BACKUP_CONFIG" "$TARGET_CONFIG"
else
  echo "No backup config.yaml found at workspace root."
  if [ ! -f "$TARGET_CONFIG" ]; then
    if [ -f "$ROOT_DIR/anman-ai/config/config.yaml" ]; then
      echo "Copying config.yaml from local project development setup..."
      cp "$ROOT_DIR/anman-ai/config/config.yaml" "$TARGET_CONFIG"
    else
      echo "Copying config.yaml.example as config.yaml..."
      cp "$WINDOWS_WORKSPACE/config/config.yaml.example" "$TARGET_CONFIG"
    fi
  fi
fi

echo "=== デプロイ完了 ==="
echo "Windows 側のデプロイ先: $WINDOWS_WORKSPACE"
echo "start.bat または start_wt.bat を起動してテストしてください。"
