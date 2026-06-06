#!/bin/bash
# start_anman_ai.sh
# run_loop.sh をバックグラウンドで起動します。

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$ROOT_DIR/anman-ai/log"
PID_FILE="$LOG_DIR/anman-ai.pid"

mkdir -p "$LOG_DIR"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "anman-ai is already running (PID: $PID)"
        exit 1
    else
        rm "$PID_FILE"
    fi
fi

# 現在のシェルで使用している ruby の絶対パスを取得
RUBY_PATH=$(which ruby)
if [ -z "$RUBY_PATH" ]; then
    RUBY_PATH="ruby"
fi

echo "Starting anman-ai in the background..."
echo "Logs will be written to: $LOG_DIR/anman-ai.log"
echo "Using ruby: $RUBY_PATH"

# 環境変数 RUBY_BIN をエクスポートして setsid で run_loop.sh を起動
export RUBY_BIN="$RUBY_PATH"
setsid "$ROOT_DIR/anman-ai/bin/run_loop.sh" > "$LOG_DIR/nohup_debug.log" 2>&1 &

# run_loop.sh が PID ファイルを書き込むまで少し待つ
sleep 1

if [ -f "$PID_FILE" ]; then
    MAIN_PID=$(cat "$PID_FILE")
    echo "anman-ai successfully started with PID $MAIN_PID."
else
    echo "Warning: PID file was not created. Check $LOG_DIR/nohup_debug.log"
fi
