#!/bin/bash
# watch_anman_ai.sh
# anman-ai の動作ログをリアルタイムで表示します。

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$ROOT_DIR/anman-ai/log/anman-ai.log"

if [ ! -f "$LOG_FILE" ]; then
    echo "Log file not found at $LOG_FILE. Is anman-ai running?"
    exit 1
fi

echo "=== Tail of anman-ai.log (Press Ctrl+C to exit) ==="
tail -f "$LOG_FILE"
