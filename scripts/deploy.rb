#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'net/ftp'
require 'fileutils'

# .env ファイルがあれば読み込む
env_file = File.expand_path('../.env', __dir__)
if File.exist?(env_file)
  File.readlines(env_file).each do |line|
    next if line.strip.empty? || line.start_with?('#')
    key, val = line.strip.split('=', 2)
    ENV[key] = val.gsub(/\A['"]|['"]\z/, '') if key && val
  end
end

FTP_HOST = ENV['FTP_HOST']
FTP_USER = ENV['FTP_USER']
FTP_PASS = ENV['FTP_PASS']
FTP_DIR  = ENV['FTP_DIR'] || '/' # ロリポップ上のアップロード先ディレクトリ

if !FTP_HOST || !FTP_USER || !FTP_PASS
  puts "エラー: FTP接続情報が設定されていません。"
  puts ".env ファイルを作成し、以下の変数を設定してください："
  puts "FTP_HOST=ftp.example.com"
  puts "FTP_USER=username"
  puts "FTP_PASS=password"
  puts "FTP_DIR=/ (任意)"
  exit 1
end

LOCAL_DIR = File.expand_path('../public_html', __dir__)

puts "=== FTP デプロイ開始 ==="
puts "接続先: #{FTP_HOST}"
puts "ユーザー: #{FTP_USER}"
puts "リモートディレクトリ: #{FTP_DIR}"
puts "ローカルディレクトリ: #{LOCAL_DIR}"
puts "--------------------------------"

def upload_directory(ftp, local_path, remote_path)
  # リモートディレクトリが存在しない場合は作成を試みる
  begin
    ftp.mkdir(remote_path)
    puts "ディレクトリ作成: #{remote_path}"
  rescue Net::FTPPermError
    # 既に存在する場合は無視
  end

  Dir.foreach(local_path) do |entry|
    next if entry == '.' || entry == '..'

    local_entry_path = File.join(local_path, entry)
    remote_entry_path = File.join(remote_path, entry)

    # Git関連ファイルはデプロイしない
    next if entry == '.gitkeep' || entry == '.gitignore' || entry.start_with?('.git')

    # aiwolf/db 配下のデータファイルおよびディレクトリはデプロイしない
    # (ただし db ディレクトリ自体は ftp.mkdir でリモートに作成されます)
    if local_path.end_with?('aiwolf/db')
      next
    end

    if File.directory?(local_entry_path)
      upload_directory(ftp, local_entry_path, remote_entry_path)
    else
      puts "アップロード中: #{entry} -> #{remote_entry_path}"
      
      # バイナリモードでアップロード
      ftp.putbinaryfile(local_entry_path, remote_entry_path)

      # 拡張子が .rb または .cgi の場合、パーミッションを 700 に設定する
      if entry.end_with?('.rb') || entry.end_with?('.cgi')
        begin
          ftp.voidcmd("SITE CHMOD 700 #{remote_entry_path}")
          puts "  -> パーミッションを 700 に設定しました"
        rescue => e
          puts "  -> [警告] パーミッション変更に失敗しました (SITE CHMOD非対応の可能性があります): #{e.message}"
        end
      end
    end
  end
end

begin
  Net::FTP.open(FTP_HOST) do |ftp|
    ftp.login(FTP_USER, FTP_PASS)
    ftp.passive = true
    
    # パッシブモードで接続
    puts "ログイン成功。デプロイを実行します..."
    
    upload_directory(ftp, LOCAL_DIR, FTP_DIR)
  end
  puts "--------------------------------"
  puts "デプロイが正常に完了しました！"
rescue => e
  puts "エラーが発生しました: #{e.message}"
  exit 1
end
