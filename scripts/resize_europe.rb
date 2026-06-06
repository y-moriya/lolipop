#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'fileutils'

# パスの定義
BASE_DIR = File.expand_path('../../public_html/aiwolf', __FILE__)
IMG_DIR = File.join(BASE_DIR, 'img')
EUROPE_DIR = File.join(IMG_DIR, 'europe')

# リサイズサイズ定義
SMALL_WIDTH  = 76
SMALL_HEIGHT = 98
LARGE_WIDTH  = 100
LARGE_HEIGHT = 128

# 元画像ファイル名番号 (XX) から、charset.rb の元配列でのインデックス (dest_idx) へのマッピング
# 名前を正として、img_filename_replace.md に基づく
MAPPING = {
  "01" => 19, # 神父 ラファエル
  "02" => 2,  # 委員長 ナディア
  "03" => 26, # 門番 ヘンリー
  "04" => 3,  # おでこ パティ
  "05" => 33, # バーテン ウォルター
  "06" => 34, # 遊び人 フィリップ
  "07" => 31, # 冒険家 ジェフ
  "08" => 15, # 放浪者 ナバール
  "09" => 30, # 巫女 サクラ
  "10" => 28, # お嬢様 エミリー
  "11" => 27, # 医師 エドワード
  "12" => 7,  # 三等兵 リルム
  "13" => 23, # 学者 カーク
  "14" => 16, # 勉強家 ザックス
  "15" => 20, # 富豪 トニー
  "16" => 12, # メイド シンデレラ
  "17" => 36, # 素浪人 キョウ
  "18" => 17, # 詩人 アルベルト
  "19" => 29, # パン屋の娘 イリーナ
  "20" => 11, # 女優 ナオミ
  "21" => 35, # シスター メリッサ
  "22" => 14, # 画家 ミユ
  "23" => 24, # ねぼすけ ノック
  "24" => 5,  # 踊り子 フローレンス
  "25" => 21, # 不審者 クリス
  "26" => 13, # おてんば カトリーヌ
  "27" => 18, # 情報屋 マイケル
  "28" => 25, # 学士 ノエル
  "29" => 8,  # 司書見習い アン
  "30" => 22, # 運び屋 イザーク
  "31" => 10, # 教師 マリア
  "32" => 32, # 漁師 ビル
  "33" => 1,  # 花売り ヘレナ
  "34" => 9,  # 保母 ミズリ
  "35" => 4,  # おばさん サンディ
  "36" => 0,  # 大工 ダグラス
  "37" => 6   # 研究員 レイ
}

puts "Starting mapping resize process..."
puts "Base directory: #{BASE_DIR}"

MAPPING.each do |xx, dest_idx|
  yy = sprintf("%02d", dest_idx)

  # コピー元とコピー先
  src_small = File.join(EUROPE_DIR, 'small', "europe_#{xx}_small.png")
  dest_small = File.join(IMG_DIR, "europe_s#{yy}.png")

  src_large = File.join(EUROPE_DIR, 'large', "europe_#{xx}_large.png")
  dest_large = File.join(IMG_DIR, "europe#{yy}.png")

  # small画像のリサイズ
  if File.exist?(src_small)
    cmd_small = "convert -resize #{SMALL_WIDTH}x#{SMALL_HEIGHT}! \"#{src_small}\" \"#{dest_small}\""
    puts "Resizing small: #{src_small} -> #{dest_small} (Mapped to: #{dest_idx})"
    system(cmd_small)
  else
    puts "Warning: #{src_small} not found"
  end

  # large画像のリサイズ
  if File.exist?(src_large)
    cmd_large = "convert -resize #{LARGE_WIDTH}x#{LARGE_HEIGHT}! \"#{src_large}\" \"#{dest_large}\""
    puts "Resizing large: #{src_large} -> #{dest_large} (Mapped to: #{dest_idx})"
    system(cmd_large)
  else
    puts "Warning: #{src_large} not found"
  end
end

puts "Mapped resize process completed."
