#!/bin/bash
# stop_anman_ai.sh
# バックグラウンドで実行中の anman-ai プロセスおよび再起動ループを停止します。

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="$ROOT_DIR/anman-ai/log/anman-ai.pid"

if [ ! -f "$PID_FILE" ]; then
    echo "anman-ai is not running (PID file not found)."
    exit 0
fi

PID=$(cat "$PID_FILE")
echo "Stopping anman-ai (PID: $PID)..."

# 起動スクリプトのサブシェル（親プロセス）と、その下で動いている ruby プロセスを停止
pkill -P "$PID" 2>/dev/null
kill "$PID" 2>/dev/null

# 確実に停止するまで少し待つ
sleep 2

if kill -0 "$PID" 2>/dev/null; then
    echo "Failed to stop process $PID. Trying force kill..."
    pkill -9 -P "$PID" 2>/dev/null
    kill -9 "$PID" 2>/dev/null
fi

rm -f "$PID_FILE"
echo "anman-ai stopped."
