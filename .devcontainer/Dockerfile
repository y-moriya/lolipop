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

# Apacheの実行ディレクトリやログディレクトリの所有権を更新
RUN chown -R www-data:www-data /var/run/apache2 /var/lock/apache2 /var/log/apache2 /var/lib/apache2

# ロリポップのRubyパス /usr/local/bin/ruby3.4 に対応するためのシンボリックリンクを作成
RUN ln -s /usr/local/bin/ruby /usr/local/bin/ruby3.4

# ロリポップの Ruby 実体パス /usr/local/ruby/3.4/bin/ruby に対応するためのディレクトリとシンボリックリンクを作成
RUN mkdir -p /usr/local/ruby/3.4/bin && \
    ln -s /usr/local/bin/ruby /usr/local/ruby/3.4/bin/ruby

# Gem.ruby や RbConfig.ruby が /usr/local/ruby/3.4/bin/ruby を返すように設定
RUN mkdir -p /usr/local/lib/ruby/site_ruby/rubygems/defaults && \
    echo "RbConfig::CONFIG['bindir'] = '/usr/local/ruby/3.4/bin'; RbConfig::CONFIG['ruby_install_name'] = 'ruby'" > /usr/local/lib/ruby/site_ruby/rubygems/defaults/operating_system.rb

# Apacheの設定ファイルを配置
COPY lolipop-cgi.conf /etc/apache2/sites-available/000-default.conf

# デフォルトのコマンドで Apache をフォアグラウンド実行（古いPIDやソケットを削除してから起動）
CMD ["/bin/sh", "-c", "rm -f /var/run/apache2/apache2.pid /var/run/apache2/socks/* && exec apache2ctl -D FOREGROUND"]

