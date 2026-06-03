# -*- coding: utf-8 -*-
PLAIN_NAMES = [
	"学者 ダニエル",
	"画家 アガサ",
	"時計職人 プリシラ",
	"雑貨屋 サラ",
	"花売り ウェンディ",
	"修道女 アイリス",
	"助手 カレン",
	"鍛冶屋 ブリジット",
	"薬剤師 シャロン",
	"帽子屋 ロレッタ",
	"靴屋の娘 リタ",
	"お嬢様 ナタリー",
	"教師 レイチェル",
	"使用人 テレサ",
	"船乗り ガイ",
	"医師 パスカル",
	"金貸し オリバー",
	"料理人 ハリー",
	"小説家 モーリス",
	"軍人 マックス",
	"酒場の主人 ワット",
	"旅芸人 ミック",
	"用心棒 フランク",
	"学生 コンラッド",
	"作曲家 ジェラール",
	"探検家 エルマー",
	"羊飼い シリル",
]

PLAIN_DUMMY = {
	"entry" => "人狼は本当にいるんだ、この論文を見てくれ！",
	"middle" => "今…だれか俺を呼ばなかったかい？",
	"next" => "おはよう。"
}

class Charset
	attr_reader :file_name, :name, :char_names, :dummy_message, :spectator_filename, :howl_filename

	def initialize(file_name, name, char_names, dummy_message, spectator, howl)
		@file_name = file_name
		@name = name
		@char_names = char_names
		@dummy_message = dummy_message
		@spectator_filename = spectator + "black"
		@howl_filename = howl + "howl"
	end

	def Charset.charsets
		@@charsets
	end

	a = Array.new
	a.push(Charset.new('plain', 'プライン', PLAIN_NAMES, PLAIN_DUMMY, '', '')) # 0
	@@charsets = a
end
