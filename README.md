# ロリポップ互換 Ruby 3.4 CGI 開発・デプロイ環境

ロリポップ！レンタルサーバーのCGI仕様に合わせたローカル開発環境（VSCode DevContainer）および、FTP自動デプロイスクリプトのセットアップです。

## 📂 ディレクトリ構成

- **[.devcontainer/](file:///home/wellk/project/lolipop/.devcontainer)** : DevContainer 設定ファイル群
  - [Dockerfile](file:///home/wellk/project/lolipop/.devcontainer/Dockerfile) : Ruby 3.4 (Debian) + Apache (CGI有効) のイメージ定義。パーミッション `700` のCGIを動かすために `www-data` のUID/GIDを `1000` に設定しています。
  - [docker-compose.yml](file:///home/wellk/project/lolipop/.devcontainer/docker-compose.yml) : ポートマッピング（ホスト 8063 -> コンテナ 80）とボリュームマウントの設定。
  - [devcontainer.json](file:///home/wellk/project/lolipop/.devcontainer/devcontainer.json) : VSCode用の接続・拡張機能設定。
  - [lolipop-cgi.conf](file:///home/wellk/project/lolipop/.devcontainer/lolipop-cgi.conf) : Apache 用のロリポップ互換CGI設定。
- **[public_html/](file:///home/wellk/project/lolipop/public_html)** : Web公開ディレクトリ（ロリポップ上の公開フォルダに対応）
  - [test.rb](file:///home/wellk/project/lolipop/public_html/test.rb) : 動作確認用の Ruby CGI スクリプト（パーミッション: `700`、シバン: `#!/usr/local/bin/ruby3.4`）。
- **[scripts/](file:///home/wellk/project/lolipop/scripts)** : ユーティリティスクリプト
  - [deploy.rb](file:///home/wellk/project/lolipop/scripts/deploy.rb) : FTP経由での自動デプロイスクリプト。転送後にCGIファイルのパーミッションを自動で `700` に変更します。
- **[.env.example](file:///home/wellk/project/lolipop/.env.example)** : FTP接続情報の環境変数テンプレート。

---

## 🚀 使い方

### 1. ローカル開発環境の起動
1. Windows 側の VSCode で本プロジェクトディレクトリを開きます。
2. 画面右下に表示される「**Reopen in Container**（コンテナで再度開く）」をクリックします。
3. 初回は自動的に Docker イメージのビルドが行われ、開発環境が起動します。

### 2. ローカルでの動作確認
開発環境が起動したら、ホスト（Windows側）のブラウザから以下のアドレスにアクセスします。
- **テストCGIページ**: http://localhost:8063/test.rb

### 3. ロリポップ！へのFTPデプロイ
1. ルートディレクトリにある `[.env.example](file:///home/wellk/project/lolipop/.env.example)` をコピーして `[.env](file:///home/wellk/project/lolipop/.env)` を作成します。
2. `[.env](file:///home/wellk/project/lolipop/.env)` にロリポップ！のFTP接続情報を記述します。
   ```env
   FTP_HOST=ftp.lolipop.jp
   FTP_USER=your-ftp-username
   FTP_PASS=your-ftp-password
   FTP_DIR=/
   ```
3. 以下のデプロイコマンドを実行します（DevContainer内、またはホスト側で実行可能です）。
   ```bash
   ruby scripts/deploy.rb
   ```
   ※アップロードされた `.rb` / `.cgi` ファイルのパーミッションは、自動的にロリポップ推奨の `700` に設定されます。
