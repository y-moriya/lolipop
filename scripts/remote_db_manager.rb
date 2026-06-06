#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'net/ftp'
require 'fileutils'

# .env をロード
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
FTP_DIR  = ENV['FTP_DIR'] || '/'

if !FTP_HOST || !FTP_USER || !FTP_PASS
  puts "エラー: FTP接続情報が設定されていません。"
  exit 1
end

REMOTE_DB_DIR = File.join(FTP_DIR, 'aiwolf/db')
LOCAL_BACKUP_DIR = File.expand_path('../backup', __dir__)
TMP_DIR = "/tmp/remote_db_backup_#{Time.now.to_i}"

def show_usage
  puts "Usage:"
  puts "  ruby #{$0} --backup      : リモートのデータベースをダウンロードして backup/ に圧縮保存します。"
  puts "  ruby #{$0} --clean       : リモートの村データ、戦績、ログ等を消去します（登録ユーザーは保持）。"
  puts "  ruby #{$0} --clean-all   : 登録ユーザーも含めて、リモートの全DBファイルを消去します。"
end

# リモートディレクトリ内のファイルを再帰的にダウンロードするヘルパー
def download_remote_dir(ftp, remote_dir, local_dir)
  FileUtils.mkdir_p(local_dir)
  begin
    ftp.chdir(remote_dir)
  rescue => e
    puts "  chdir 失敗: #{remote_dir} (#{e.message})"
    return
  end

  entries = ftp.nlst rescue []
  entries.each do |entry|
    next if entry == '.' || entry == '..'
    
    # ディレクトリかどうか判定
    is_dir = false
    begin
      ftp.chdir(entry)
      is_dir = true
      ftp.chdir('..')
    rescue
    end

    local_path = File.join(local_dir, entry)
    remote_path = File.join(remote_dir, entry)

    if is_dir
      download_remote_dir(ftp, remote_path, local_path)
      # ダウンロード後は上の親に戻っておく
      ftp.chdir(remote_dir) rescue nil
    else
      puts "ダウンロード中: #{remote_path} -> #{local_path}"
      begin
        ftp.getbinaryfile(entry, local_path)
      rescue => e
        puts "  ダウンロード失敗: #{entry} (#{e.message})"
      end
    end
  end
end

# リモートディレクトリの中身をクリーンアップするヘルパー
def clean_remote_dir(ftp, remote_dir, keep_user_db)
  begin
    ftp.chdir(remote_dir)
  rescue => e
    puts "  chdir 失敗: #{remote_dir} (#{e.message})"
    return
  end

  entries = ftp.nlst rescue []
  entries.each do |entry|
    next if entry == '.' || entry == '..'
    next if entry == '.gitkeep'

    is_dir = false
    begin
      ftp.chdir(entry)
      is_dir = true
      ftp.chdir('..')
    rescue
    end

    remote_path = File.join(remote_dir, entry)

    if is_dir
      # サブディレクトリ内の中身をクリーンアップ
      clean_remote_dir(ftp, remote_path, keep_user_db)
      ftp.chdir(remote_dir) rescue nil
    else
      if entry == 'user.db' && keep_user_db
        puts "  保持: #{remote_path}"
        next
      end

      puts "削除中: #{remote_path}"
      begin
        ftp.delete(entry)
      rescue => e
        puts "  削除失敗: #{entry} (#{e.message})"
      end
    end
  end
end

# メイン処理
cmd = ARGV[0]
if cmd != '--backup' && cmd != '--clean' && cmd != '--clean-all'
  show_usage
  exit 1
end

begin
  Net::FTP.open(FTP_HOST) do |ftp|
    ftp.login(FTP_USER, FTP_PASS)
    ftp.passive = true
    puts "FTPログイン成功."

    if cmd == '--backup'
      puts "=== リモートDBのダウンロードバックアップを開始します ==="
      download_remote_dir(ftp, REMOTE_DB_DIR, TMP_DIR)
      
      # tar.gz 圧縮ファイルの作成
      backup_filename = "remote_db_backup_#{Time.now.strftime('%Y%m%d_%H%M%S')}.tar.gz"
      backup_filepath = File.join(LOCAL_BACKUP_DIR, backup_filename)
      
      FileUtils.mkdir_p(LOCAL_BACKUP_DIR)
      puts "バックアップファイルを圧縮中..."
      system("tar -czf #{backup_filepath} -C #{File.dirname(TMP_DIR)} #{File.basename(TMP_DIR)}")
      
      if File.exist?(backup_filepath)
        puts "✅ バックアップ完了: #{backup_filepath}"
      else
        puts "❌ 圧縮に失敗しました。"
      end
      
      # 一時フォルダの削除
      FileUtils.rm_rf(TMP_DIR)

    elsif cmd == '--clean' || cmd == '--clean-all'
      keep_user = (cmd == '--clean')
      puts "=== リモートDBのクリーンアップを開始します (keep_user_db: #{keep_user}) ==="
      
      clean_remote_dir(ftp, REMOTE_DB_DIR, keep_user)
      puts "✅ リモートDB의 クリーンアップが完了しました。"
    end
  end
rescue => e
  puts "エラーが発生しました: #{e.message}"
  puts e.backtrace.join("\n")
  exit 1
end
