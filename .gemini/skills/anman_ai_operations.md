# anman-ai 運用スキル

このスキルは anman-ai（人狼AI自律クライアント）および aiwolf CGI の日常的な起動・停止・監視・デプロイ操作を定義します。
ユーザーが anman-ai の起動・停止・再起動・ログ確認・デプロイを依頼した際は、このスキルの手順に従ってください。

---

## 前提

- すべてのコマンドはプロジェクトルート `/home/wellk/project/lolipop` で実行します。
- anman-ai の設定ファイルは `anman-ai/config/config.yaml` です。
- ログファイルは `anman-ai/log/anman-ai.log` に出力されます。
- PID ファイルは `anman-ai/log/anman-ai.pid` で管理されます。

---

## 1. anman-ai を起動する

バックグラウンドで起動します（再起動ループ付き）。

```bash
cd /home/wellk/project/lolipop && ./start_anman_ai.sh
```

**成功の確認**: 「anman-ai successfully started with PID XXXXX.」と表示されること。

---

## 2. anman-ai を停止する

```bash
cd /home/wellk/project/lolipop && ./stop_anman_ai.sh
```

**成功の確認**: 「anman-ai stopped.」と表示されること。

---

## 3. anman-ai を再起動する（修正後などに使用）

```bash
cd /home/wellk/project/lolipop && ./stop_anman_ai.sh && sleep 2 && ./start_anman_ai.sh
```

---

## 4. anman-ai のログをリアルタイムで監視する

```bash
cd /home/wellk/project/lolipop && ./watch_anman_ai.sh
```

または直接 tail:
```bash
tail -f /home/wellk/project/lolipop/anman-ai/log/anman-ai.log
```

直近 N 行を確認する場合:
```bash
tail -50 /home/wellk/project/lolipop/anman-ai/log/anman-ai.log
```

---

## 5. anman-ai の動作状態を確認する

```bash
ps aux | grep anman-ai | grep -v grep
```

---

## 6. Apache エラーログを確認する（aiwolf CGI のサーバーエラー調査）

```bash
cd /home/wellk/project/lolipop && ./show_logs.sh
```

引数で行数指定（例: 最新200行）:
```bash
cd /home/wellk/project/lolipop && ./show_logs.sh 200
```

---

## 7. aiwolf CGI を本番サーバーへデプロイする

```bash
cd /home/wellk/project/lolipop && ruby scripts/deploy.rb
```

**成功の確認**: 「デプロイが正常に完了しました！」と出力されること。
**前提**: プロジェクトルートの `.env` ファイルに正しい FTP ホスト・ユーザー・パスワード・パスが設定されていること。

---

## 8. ライフサイクルテストを実行する

テスト村を自動作成し、入村〜感想戦までの一連の動作を自動検証します。

```bash
cd /home/wellk/project/lolipop && ./test_lifecycle.sh
```

---

## 9. 本番DBのバックアップを取得・ログを閲覧する

```bash
cd /home/wellk/project/lolipop && ruby scripts/remote_db_manager.rb --backup
```

---

## 10. ローカルDBのクリーンアップ（テスト環境リセット）

```bash
cd /home/wellk/project/lolipop && ruby scripts/clean_db.rb
```

---

## よくある問題と対処法

| 症状 | 原因 | 対処 |
|---|---|---|
| `undefined method 'find_active_joined_village'` | client.rb のメソッド欠落 | client.rb を確認・修正後に再起動 |
| `[Fatal Error]` ループ | 起動直後のクラッシュ → 再起動ループ中 | ログを tail で確認してエラー内容を特定 |
| LLM が空レスポンスを返す | Ollama が落ちている | Windows 側で Ollama を再起動する |
| 自己投票・自己占いが起きる | @userid とキャラクター名の不一致 | client.rb の比較を @game_state.my_name に修正（修正済み）|
| エピローグで連投ループ | is_mine フラグ未参照 | client.rb の is_mine フラグ判定を確認（修正済み）|
