#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'fileutils'

# CGIのdbディレクトリへのパス
DB_DIR = File.expand_path('../public_html/aiwolf/db', __dir__)

puts "--- データベースとログの初期化を開始します ---"

# 1. グローバルDBとユーザーDBの削除
['user.db', 'vil.db'].each do |db_file|
  path = File.join(DB_DIR, db_file)
  if File.exist?(path)
    File.delete(path)
    puts "削除しました: #{db_file}"
  end
end

# 2. サブディレクトリ（vil0, log0など）の中身をクリアする
Dir.glob(File.join(DB_DIR, '*')).each do |dir|
  next unless File.directory?(dir)
  
  puts "ディレクトリをクリア中: #{File.basename(dir)}"
  Dir.glob(File.join(dir, '*')).each do |file|
    next if File.basename(file) == '.gitkeep'
    
    if File.directory?(file)
      FileUtils.rm_rf(file)
    else
      File.delete(file)
    end
    puts "  - 削除しました: #{File.basename(file)}"
  end
end

puts "--- 初期化が完了しました ---"
