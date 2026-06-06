# AI人狼クライアントおよびCGI 開発・運用スキルガイド

このドキュメントは、別のセッションのAIエージェントが `IsSkillFile: true` で読み込んで、ビルド、テスト、デプロイなどのスクリプトを実行するための手順書（Skillファイル）です。

---

## 1. データベースのクリーンアップ (ローカルテスト環境)
ローカルのテスト用PStoreデータベース（村データ・ユーザーデータ）およびHTMLログを初期化します。

### 実行手順
プロジェクトのルートディレクトリで以下のコマンドを実行してください。
```bash
ruby scripts/clean_db.rb
```

---

## 2. anman-ai の起動

AIクライアントをバックグラウンドの再起動ループ付きで起動します。

### 実行手順
```bash
./start_anman_ai.sh
```
- 成功すると「anman-ai successfully started with PID XXXXX.」と表示されます。
- ログは `anman-ai/log/anman-ai.log` に書き込まれます。

---

## 3. anman-ai の停止

```bash
./stop_anman_ai.sh
```
- 成功すると「anman-ai stopped.」と表示されます。

---

## 4. anman-ai の再起動（コード修正後など）

```bash
./stop_anman_ai.sh && sleep 2 && ./start_anman_ai.sh
```

---

## 5. anman-ai のログ監視（リアルタイム）

```bash
./watch_anman_ai.sh
```
または直接:
```bash
tail -f anman-ai/log/anman-ai.log
```
直近 N 行のみ確認する場合:
```bash
tail -50 anman-ai/log/anman-ai.log
```

---

## 6. anman-ai の動作状態確認

```bash
ps aux | grep anman-ai | grep -v grep
```

---

## 7. 長期自律プレイ検証テストの実行
5人牛村（占い1、狂人1、人狼1、市民2）のテスト村を作成し、NPCプレイヤーとの対話、沈黙タイムアウト時の能動的発言、自動投票、死者のうめき、感想戦対話までの一連のライフサイクルを自動検証します。

### 実行手順
```bash
./test_lifecycle.sh
```
（または直接 `ruby scripts/test_autonomous_lifecycle.rb`）
- テストが完了すると、コンソールに `自律長期ライフサイクル検証テストが完了しました！ (成功)` と出力され、終了コード `0` で正常終了します。

---

## 8. CGI（aiwolf）の外部サーバーへのデプロイ
CGI（`public_html/aiwolf`）の最新ソースコードを本番のロリポップホスティングサーバーへFTPアップロードし、CGIの実行権限（CHMOD 700）を自動で設定します。

### 事前準備
プロジェクトルートの `.env` ファイルに正しいFTPホスト、ユーザー、パスワード、およびディレクトリパスが記載されていることを確認してください。

### 実行手順
```bash
ruby scripts/deploy.rb
```
- アップロードが成功すると、コンソールに `デプロイが正常に完了しました！` と出力されます。

---

## 9. 本番DBのバックアップ取得・ログ閲覧

```bash
ruby scripts/remote_db_manager.rb --backup
```

---

## 10. Apache エラーログの確認（CGIサーバーエラー調査）

```bash
./show_logs.sh
```
行数を指定する場合（例: 最新200行）:
```bash
./show_logs.sh 200
```

---

## よくある問題と対処法

| 症状 | 原因 | 対処 |
|---|---|---|
| `undefined method 'find_active_joined_village'` | client.rb のメソッド欠落 | client.rb を確認・修正後に再起動 |
| `[Fatal Error]` ループ | 起動直後のクラッシュ → 再起動ループ中 | ログを tail で確認してエラー内容を特定 |
| LLM が空レスポンスを返す | Ollama が落ちている | Windows 側で Ollama を再起動する |
| 自己投票・自己占いが起きる | @userid とキャラクター名不一致 | client.rb の比較を `@game_state.my_name` に修正（修正済み） |
| エピローグで連投ループ | is_mine フラグ未参照 | client.rb の is_mine チェックを確認（修正済み） |

