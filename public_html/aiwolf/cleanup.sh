#!/bin/bash
# ==============================================================================
# 人狼ゲームデータベース バックアップ＆クリーンアップスクリプト
# ==============================================================================

# スクリプトのディレクトリを基準にする
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

DB_DIR="./db"
BACKUP_DIR="."

show_usage() {
    echo "Usage:"
    echo "  $0 --backup      : データベースの圧縮バックアップのみを作成します。"
    echo "  $0 --clean       : 村データとログ、戦績を消去します（登録ユーザーは保持）。"
    echo "  $0 --clean-all   : 登録ユーザー(user.db)も含めてすべて消去します。"
    echo "  $0 --delete-bak  : 作成したバックアップファイルをサーバーから削除します。"
}

if [ -z "$1" ]; then
    show_usage
    exit 1
fi

case "$1" in
    --backup)
        echo "=== 1. データベースバックアップの作成 ==="
        BACKUP_NAME="db_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
        
        if [ ! -d "$DB_DIR" ]; then
            echo "❌ データベースディレクトリ ($DB_DIR) が存在しません。"
            exit 1
        fi
        
        echo "データベースを圧縮しています..."
        tar -czf "$BACKUP_DIR/$BACKUP_NAME" "$DB_DIR"
        
        if [ $? -eq 0 ]; then
            echo "✅ バックアップの作成に成功しました！"
            echo "   ファイル名: $BACKUP_NAME"
            echo "   ダウンロードURL: https://wolften.secret.jp/aiwolf/$BACKUP_NAME"
            echo ""
            echo "⚠️ [重要] 以下の手順で行ってください:"
            echo "1. 上記のURLをブラウザで開いて、バックアップをローカルPCにダウンロードして保管してください。"
            echo "2. ダウンロード完了後、クリーンアップを実行するには以下を実行してください:"
            echo "   $0 --clean (または --clean-all)"
            echo "3. 最後に、サーバー上に残ったバックアップファイルを削除するために以下を実行してください:"
            echo "   $0 --delete-bak"
        else
            echo "❌ 圧縮処理中にエラーが発生しました。"
            exit 1
        fi
        ;;

    --clean|--clean-all)
        echo "=== 2. データベースのクリーンアップ ==="
        echo "⚠️ 本番データを消去します。バックアップをダウンロード済みであることを確認してください。"
        
        # 非インタラクティブ実行のために環境変数か引数での確認も可能にしておく
        if [ "$FORCE" != "1" ]; then
            read -p "本当に続行しますか？ (y/N): " confirm
            if [[ ! "$confirm" =~ ^[yY]$ ]]; then
                echo "キャンセルしました。"
                exit 0
            fi
        fi

        echo "クリーンアップを実行しています..."

        # 個別村のデータベース消去
        if [ -d "$DB_DIR/vil0" ]; then
            echo "- 個別村DB (vil0/*) の消去..."
            find "$DB_DIR/vil0" -type f ! -name ".gitkeep" -delete
        fi

        # 村ログの消去
        if [ -d "$DB_DIR/log0" ]; then
            echo "- 村ログ (log0/*) の消去..."
            find "$DB_DIR/log0" -type f ! -name ".gitkeep" -delete
        fi

        # 村リスト、戦績、プロフィールの消去
        echo "- 村リスト (vil.db) の削除..."
        rm -f "$DB_DIR/vil.db"

        echo "- 戦績 (record.db) の削除..."
        rm -f "$DB_DIR/record.db"

        echo "- プロフィール (profile.db) の削除..."
        rm -f "$DB_DIR/profile.db"

        if [ "$1" == "--clean-all" ]; then
            echo "- ⚠️ ユーザーデータベース (user.db) の削除..."
            rm -f "$DB_DIR/user.db"
        else
            echo "- ユーザーデータベース (user.db) は保持されました。"
        fi

        echo ""
        echo "✅ クリーンアップが完了しました。"
        echo "   サーバー上で作成したバックアップファイルがある場合、削除をお忘れなく。"
        ;;

    --delete-bak)
        echo "=== 3. バックアップファイルの削除 ==="
        find "$BACKUP_DIR" -name "db_backup_*.tar.gz" -type f | while read -r file; do
            echo "削除中: $file"
            rm -f "$file"
        done
        echo "✅ サーバー上のバックアップファイルを削除しました。"
        ;;

    *)
        show_usage
        exit 1
        ;;
esac
