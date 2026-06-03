FROM ruby:3.4-bookworm

# Apacheと必要なパッケージをインストール
RUN apt-get update && apt-get install -y \
    apache2 \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# ApacheのCGIモジュールを有効化
RUN a2enmod cgi

# www-dataのUID/GIDをホスト側のオーナー(1000)に合わせる
# これにより、パーミッション700のCGIスクリプトを実行可能にする
RUN usermod -u 1000 www-data && groupmod -g 1000 www-data

# ロリポップのRubyパス /usr/local/bin/ruby3.4 に対応するためのシンボリックリンクを作成
RUN ln -s /usr/local/bin/ruby /usr/local/bin/ruby3.4

# Apacheの設定ファイルを配置
COPY lolipop-cgi.conf /etc/apache2/sites-available/000-default.conf

# デフォルトのコマンドで Apache をフォアグラウンド実行
CMD ["apache2ctl", "-D", "FOREGROUND"]
