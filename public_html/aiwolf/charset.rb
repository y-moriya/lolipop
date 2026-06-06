# -*- coding: utf-8 -*-
EUROPE_NAMES = [
	"大工 ダグラス",
	"花売り ヘレナ",
	# "少女 アリス",
	"委員長 ナディア",
	"おでこ パティ",
	"おばさん サンディ",
	"踊り子 フローレンス",
	"研究員 レイ",
	"三等兵 リルム",
	"司書見習い アン",
	"保母 ミズリ",
	"教師 マリア",
	"女優 ナオミ",
	"メイド シンデレラ",
	"おてんば カトリーヌ",
	"画家 ミユ",
	"放浪者 ナバール",
	"勉強家 ザックス",
	"詩人 アルベルト",
	"情報屋 マイケル",
	"神父 ラファエル",
	"富豪 トニー",
	# "悪ガキ ウィリアム",
	"不審者 クリス",
	"運び屋 イザーク",
	# "孤児 オスカー",
	"学者 カーク",
	"ねぼすけ ノック",
	"学士 ノエル",
	"門番 ヘンリー",
	"医師 エドワード",
	"お嬢様 エミリー",
	"パン屋の娘 イリーナ",
	"巫女 サクラ",
	# "坊ちゃん ニコル",
	"冒険家 ジェフ",
	"漁師 ビル",
	"バーテン ウォルター",
	"遊び人 フィリップ",
	"シスター メリッサ",
	"素浪人 キョウ"
]

EUROPE_DUMMY = {
	"entry" => "人狼なんて、本当にいるのかい？",
	"middle" => "今…だれか俺を呼ばなかったかい？",
	"next" => "俺……この人狼騒ぎが収まったら、結婚するんだ。"
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
	a.push(Charset.new('europe', '欧州AIリマスタード', EUROPE_NAMES, EUROPE_DUMMY, '', '')) # 0
	@@charsets = a
end
