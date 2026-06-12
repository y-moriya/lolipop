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

echo "=== 3.5. 既存設定ファイルの退避 ==="
BACKUP_DIR="/mnt/c/Users/wellk/workspace/config_backup"
BACKUP_CONFIG="/mnt/c/Users/wellk/workspace/config.yaml"
CURRENT_CONFIG="$WINDOWS_WORKSPACE/config/config.yaml"

mkdir -p "$BACKUP_DIR"

if [ -f "$CURRENT_CONFIG" ]; then
  echo "Backing up current config.yaml to $BACKUP_CONFIG and $BACKUP_DIR..."
  cp "$CURRENT_CONFIG" "$BACKUP_CONFIG"
  cp "$CURRENT_CONFIG" "$BACKUP_DIR/config.yaml"
else
  echo "No existing config.yaml found."
fi

if [ -d "$WINDOWS_WORKSPACE/config" ]; then
  echo "Backing up other configuration files under config/..."
  (
    shopt -s nullglob
    for f in "$WINDOWS_WORKSPACE/config"/config.*.yml; do
      echo "Backing up $(basename "$f")..."
      cp "$f" "$BACKUP_DIR/"
    done
  )
fi

echo "=== 4. Windows ホスト Workspace への上書きコピー ==="
mkdir -p "$WINDOWS_WORKSPACE"
cp -r "$TEMP_DIR/extracted/anman-ai-snapshot-windows"/* "$WINDOWS_WORKSPACE/"

echo "=== 5. 設定ファイルの復元・マージ ==="
ruby -ryaml -rfileutils -e '
  backup_dir = ARGV[0]
  target_dir = ARGV[1]
  backup_config = ARGV[2]

  def deep_merge(target_hash, source_hash)
    target_hash.merge(source_hash) do |key, oldval, newval|
      if oldval.is_a?(Hash) && newval.is_a?(Hash)
        deep_merge(oldval, newval)
      else
        newval
      end
    end
  end

  def merge_yaml(backup_path, target_path)
    backup = YAML.load_file(backup_path) rescue nil
    target = YAML.load_file(target_path) rescue nil

    if backup && target
      merged = deep_merge(target, backup)
      File.write(target_path, YAML.dump(merged))
      puts "Successfully merged #{File.basename(backup_path)} into #{target_path}"
    else
      puts "\e[31m[WARNING] #{File.basename(backup_path)} could not be merged!\e[0m"
      puts "\e[31mOverwriting #{target_path} with raw backup file to preserve credentials.\e[0m"
      FileUtils.cp(backup_path, target_path) if File.exist?(backup_path)
    end
  end

  if Dir.exist?(backup_dir) && !Dir.glob(File.join(backup_dir, "*.{yaml,yml}")).empty?
    Dir.glob(File.join(backup_dir, "*.{yaml,yml}")).each do |backup_path|
      filename = File.basename(backup_path)
      target_path = File.join(target_dir, filename)
      if File.exist?(target_path)
        merge_yaml(backup_path, target_path)
      else
        puts "Restoring configuration file #{filename} from backup..."
        FileUtils.cp(backup_path, target_path)
      end
    end
  elsif File.exist?(backup_config)
    target_path = File.join(target_dir, "config.yaml")
    merge_yaml(backup_config, target_path)
  else
    puts "No backup configuration found to merge/restore."
  end
' "$BACKUP_DIR" "$WINDOWS_WORKSPACE/config" "$BACKUP_CONFIG"

# Fallback: if config.yaml was not created or restored, ensure a default exists
TARGET_CONFIG="$WINDOWS_WORKSPACE/config/config.yaml"
if [ ! -f "$TARGET_CONFIG" ]; then
  if [ -f "$ROOT_DIR/anman-ai/config/config.yaml" ]; then
    echo "Copying config.yaml from local project development setup..."
    cp "$ROOT_DIR/anman-ai/config/config.yaml" "$TARGET_CONFIG"
  else
    echo "Copying config.yaml.example as config.yaml..."
    cp "$WINDOWS_WORKSPACE/config/config.yaml.example" "$TARGET_CONFIG"
  fi
fi

echo "=== デプロイ完了 ==="
echo "Windows 側のデプロイ先: $WINDOWS_WORKSPACE"
echo "start.bat または start_wt.bat を起動してテストしてください。"
