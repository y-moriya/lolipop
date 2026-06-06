#!/bin/bash
# run_loop.sh
# anman-ai を自動再起動付きで実行します。

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$ROOT_DIR/anman-ai/log"
LOG_FILE="$LOG_DIR/anman-ai.log"
PID_FILE="$LOG_DIR/anman-ai.pid"

mkdir -p "$LOG_DIR"

# 自身の PID を書き込む
echo "$$" > "$PID_FILE"

# start_anman_ai.sh から渡された RUBY_BIN を使用、なければデフォルト의 ruby
RUBY_CMD="${RUBY_BIN:-ruby}"

while true; do
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting anman-ai player..." >> "$LOG_FILE"
    "$RUBY_CMD" "$ROOT_DIR/anman-ai/bin/anman-ai" >> "$LOG_FILE" 2>&1
    EXIT_CODE=$?
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] anman-ai exited with code $EXIT_CODE. Restarting in 5 seconds..." >> "$LOG_FILE"
    sleep 5
done
