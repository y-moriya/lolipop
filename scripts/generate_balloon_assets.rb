#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'fileutils'

IMG_DIR = File.expand_path('../../public_html/aiwolf/img', __FILE__)
FileUtils.mkdir_p(IMG_DIR)

puts "Generating balloon asset images in #{IMG_DIR}..."

# 各種発言の色定義
COLORS = {
  'say'     => '#ffffff',
  'whisper' => '#ff7777',
  'groan'   => '#9fb7cf',
  'think'   => '#939393'
}

COLORS.each do |prefix, color|
  # 00.jpg (ツノ画像 16x20)
  # 背景は黒、右向きの三角形（メッセージに向かって伸びるツノ）
  cmd_00 = "convert -size 16x20 xc:black -fill \"#{color}\" -draw \"polygon 0,4 0,16 16,10\" \"#{IMG_DIR}/#{prefix}00.jpg\""
  system(cmd_00)

  # 05.jpg (上部角丸枠 464x8)
  # 464x16の角丸長方形を描いて上半分を切り取る
  cmd_05 = "convert -size 464x16 xc:black -fill \"#{color}\" -draw \"roundrectangle 0,0 463,15 8,8\" -crop 464x8+0+0 \"#{IMG_DIR}/#{prefix}05.jpg\""
  system(cmd_05)

  # 06.jpg (下部角丸枠 464x8)
  # 464x16の角丸長方形を描いて下半分を切り取る
  cmd_06 = "convert -size 464x16 xc:black -fill \"#{color}\" -draw \"roundrectangle 0,0 463,15 8,8\" -crop 464x8+0+8 \"#{IMG_DIR}/#{prefix}06.jpg\""
  system(cmd_06)
end

# 個別パーツ用 (通常発言の白のみ使用)
# say00b.jpg (ツノ画像 16x20、say00.jpg と同一でOK)
FileUtils.cp("#{IMG_DIR}/say00.jpg", "#{IMG_DIR}/say00b.jpg")

# say01.jpg (左上角丸 8x8)
# 中心が右下(8,8)で半径8の円
cmd_s01 = "convert -size 8x8 xc:black -fill white -draw \"circle 8,8 8,0\" \"#{IMG_DIR}/say01.jpg\""
system(cmd_s01)

# say02.jpg (右上角丸・右下角丸兼用 8x8)
# 中心が左下(0,8)で半径8 of 円
cmd_s02 = "convert -size 8x8 xc:black -fill white -draw \"circle 0,8 0,0\" \"#{IMG_DIR}/say02.jpg\""
system(cmd_s02)

# say03.jpg (下境界線用 1x8 白)
cmd_s03 = "convert -size 1x8 xc:white \"#{IMG_DIR}/say03.jpg\""
system(cmd_s03)

# say04.jpg (右境界線用 8x1 白)
cmd_s04 = "convert -size 8x1 xc:white \"#{IMG_DIR}/say04.jpg\""
system(cmd_s04)

puts "Balloon asset generation completed!"
