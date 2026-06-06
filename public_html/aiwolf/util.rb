# -*- coding: utf-8 -*-
require 'erb'

CUSTOM = 0
POSTING = 5
WIDE_CUSTOM = 6
RANDOM = 7

LONG = 60
SAY_FULL_NUM = 30
ACTION_FULL_NUM = 30
PRV_LEN = 600
SMALL_VOICE = 'AA'

ALL_DAY_PERIOD = 24 * 60
LIST_WIDTH = 200
USE_GZIP = false
DEBUG = false
DEBUG_SHORT = false
MASTER = "DUMMY"
ADMIN = "euro"

POSTPOS = [
	"は、",
	"が、",
	"　"
]

OPENING = "人狼、それは人のふりをすることができる伝説の狼。<br>その人狼がこの村に紛れ込んでいるという噂がどこからともなく広がりました。<br>村人達は半信半疑ながらも、集会所に集まって話し合いをすることにしました。"
FOLK_WIN = "すべての人狼を退治しました。<br>多くの犠牲の上に、ついに村に平和が訪れました。"
WOLF_WIN = "もう人狼に抵抗できるほど村人は残っていません。<br>人狼は残った村人をすべて喰らい尽くし、新たな獲物を求めてこの村を去っていきました。"
YOKO_WIN_F = "すべての人狼を退治しました。<br>多くの犠牲を重ね、ついに村に平和が訪れたかのように見えました。<br>しかし、村にはまだ妖魔がひっそりと生き残っていました。"
YOKO_WIN_W = "もう人狼に抵抗できるほど村人は残っていません。<br>生き残った村人もすべて人狼に襲われてしまいました。<br>しかし、その人狼もまた村に潜んでいた妖魔によって滅ぼされました。"
LOVE_WIN = "愛の前ではすべてのものが無力でした。"

RANDOM_MSG = "どうやらこの村には、人狼と占い師が最低1人ずついるようですが、他はわかりません。ダミーの役職もランダムです。"

HEAD1 = <<END
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<html lang="ja">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
<meta http-equiv="Content-Script-Type" content="text/javascript">
<meta http-equiv="Content-Style-Type" content="text/css">
<link rel="stylesheet" type="text/css" href="plugin/base.css">
<script type="text/javascript" src="plugin/jquery.js"> </script>
<script type="text/javascript" src="plugin/script.js"> </script>
END

HEAD2ED = <<END
</head>
<body onLoad='compChange();'>
END

HEAD2VIL = <<END
</head>
<body onLoad='init();'>
END

HEAD2 = <<END
</head>
<body>
END

FOOT = <<END
</body>
</html>
END

SHOW_UPDATE_SCRIPT = %Q(
<script>
<!--
function showUpdateTimer() {
	var resttimeSpan = document.getElementById("resttime");
	if (!resttimeSpan.innerHTML.match(/([0-9]+)時間 ([0-9]+)分 ([0-9]+)秒/)) {
		return;
	}
	hour = parseInt(RegExp.$1);
	min = parseInt(RegExp.$2);
	sec = parseInt(RegExp.$3);
	sec -= 1;
	if (sec == -1) {
		sec = 59;
		min -= 1;
		if (min == -1) {
			min = 59;
			hour -= 1;
			if (hour == -1) {
            	return;
			}
		}
	}
	resttimeSpan.innerHTML = hour + '時間 ' + min + '分 ' + sec + '秒';
	setTimeout('showUpdateTimer();', 1000);
}
setTimeout('showUpdateTimer();', 1000);
// -->
</script>
)

def two(n)
	s = n.to_s
	if (s.size < 2)
		'0' + s
	else
	s
	end
end

class String
	def jcut
		if (self =~ /^((.){20})./)
			$1 + '...'
		else
			self
		end
	end
	def acut
		if (self =~ /^((.){50})./)
			$1
		else
			self
		end
	end
	def fortune!
		self.sub!(/\[ayano\]/){
			"<b>#{rand(101)}</b>"
		}
	end
	def vil_url!
		self.sub!(/\[(\d{1,5})村?\]|http:\/\/(euroz.sakura.ne.jp\/wolf|euros.x0.com)\/index.rb\?vil_id=(\d{1,5})[0-9A-Za-z_=#(&amp;)]*/){
			vil_id = ($1) ? $1 : $3
			%Q(<a href="http://euroz.sakura.ne.jp/wolf/index.rb?vil_id=#{vil_id}#form" class="say" target="_blank">[人狼@ゆとり #{vil_id}村]</a>)
		}
	end
end

def announce(str)
	%Q(<!--say--><div class="announce">#{str}</div>\n)
end
def act_announce(str, id)
	%Q(<!--say#{id}--><div class="announce">#{str}</div>\n)
end
def win_announce(str)
	%Q(<!--say--><div class="announce win">#{str}</div>\n)
end
def victim_announce(str)
	%Q(<!--say--><div class="announce whisper">#{str}</div>\n)
end
def execution_announce(str)
	%Q(<!--say--><div class="announce vote">#{str}</div>\n)
end
def dead_announce(str)
	%Q(<!--say--><div class="announce vote">#{str}</div>\n)
end
def whisper_announce(str)
	%Q(<!--whisper--><div class="announce whisper">#{str}</div>\n)
end
def fanatic_announce(str)
	%Q(<!--fanatic--><div class="announce whisper">#{str}</div>\n)
end
def fortune_announce(str, id)
	%Q(<!--think#{id}--><div class="announce fortune">#{str}</div>\n)
end
def fortune_id_announce(str, id)
	%Q(<!--think#{id}--><div class="announce fortune_id">#{str}</div>\n)
end
def guard_announce(str, id)
	%Q(<!--think#{id}--><div class="announce guard">#{str}</div>\n)
end
def safety_announce(str)
	%Q(<!--say--><div class="announce safety">#{str}</div>\n)
end
def spirit_announce(str)
	%Q(<!--sprit--><div class="announce spirit">#{str}</div>\n)
end
def free_announce(str, id)
	%Q(<!--think#{id}--><div class="announce free">#{str}</div>\n)
end
def stigmata_announce(str, id)
	%Q(<!--think#{id}--><div class="announce stigmata">#{str}</div>\n)
end
def gammer_announce(str, id)
	%Q(<!--think#{id}--><div class="announce gammer">#{str}</div>\n)
end
def cupid_announce(str, id = nil)
	if (id)
		%Q(<!--think#{id}--><div class="announce cupid">#{str}</div>\n)
	else
		%Q(<!--say--><div class="announce cupid">#{str}</div>\n)
	end
end
def possessed_announce(str, id)
	%Q(<!--think#{id}--><div class="announce possessed">#{str}</div>\n)
end
def secret_announce(str)
	%Q(<!--think00--><div class="announce">#{str}</div>\n)
end
def time_announce(str)
	%Q(<div class="time_announce">#{str}</div>\n)
end
def alllog_announce(str)
	%Q(<div class="alllog_announce">#{str}</div>\n)
end
def setvote(id, str)
	%Q(<!--think#{id}--><div class="announce vote">#{str}</div>\n)
end
def howl_wolf(howl_filename)
	%Q(<table class="message"><tr><td width="100" rowspan="2"><img src="img/#{howl_filename}.png"></td><td colspan="2" class="howl">狼の遠吠え</td></tr><tr><td width="16"><img src="img/whisper00.jpg"></td><td width="584"><div class="mes_whisper_body0"><div class="mes_whisper_body1">わおーん</div></div></td></tr></table>\n)
end

def vil_list(v)
	vilid = %Q(<a class="vid" href="?vid=#{v['vid']}&amp;date=0">#{v['vid']}村</a>)
	if (v['state'] > 2)
		if (v['sname'].size > 20)
			sname = %Q(<a href="?vid=#{v['vid']}&amp;date=1&amp;log=all" title="#{v['name']}">#{v['sname']}</a>)
		else
			sname = %Q(<a href="?vid=#{v['vid']}&amp;date=1&amp;log=all">#{v['sname']}</a>)
		end
	else
		if (v['sname'].size > 20)
			sname = %Q(<a href="?vid=#{v['vid']}#form" title="#{v['name']}">#{v['sname']}</a>)
		else
			sname = %Q(<a href="?vid=#{v['vid']}#form">#{v['sname']}</a>)
		end
	end

	card = (v['card']) ? 'CARD' : 'BBS'
	comp = Composition.compositions[v['composition']].name
	dummy = (v['dummy']) ? 'ダミーあり' : 'ダミーなし'
	char = Charset.charsets[v['char']].name
	open_id = (v['open_id']) ? 'ID公開' : ''

	start =
	if (v['upstart_time'])
		"#{v['start_hour']}時 #{v['start_min']}分開始"
	else
		"手動開始"
	end
	num = (v['state'] == 0) ? "#{v['player_num']}/#{v['entry_max']}人" : "#{v['player_num']}人"

	time =
		if (v['period'] % 60 == 0)
			"昼#{v['period'] / 60}時間"
		else
			"昼#{v['period']}分"
		end
	if (v['night_period'].to_i != 0)
		night_period =
			if (v['night_period'] % 60 == 0)
				"夜#{v['night_period'] / 60}時間"
			else
				"夜#{v['night_period']}分"
			end
		night_period = "(#{night_period}+#{v['life_period']}秒*人)" if (v['life_period'].to_i != 0)
		time += "/#{night_period}"
	end
	"<tr><td>#{vilid}</td><td>#{sname}</td><td>#{time}</td><td>#{card}</td><td>#{comp}</td><td>#{dummy}</td><td>#{char}</td><td>#{num}</td><td>#{start}</td><td>#{open_id}</td></tr>"
end

def settarget(player, t_name = nil)
	if(player.sid == 1)
		if(t_name)
			str = "#{player.name} は #{t_name} を襲撃します。"
		else
			str = "#{player.name} は襲撃対象選択を取り消します。"
		end
		%Q(<!--think#{player.num_id}--><div class="announce whisper">#{str}</div>\n)
	elsif(player.sid == 2)
		if(t_name)
			str = "#{player.name} は #{t_name} を占います。"
		else
			str = "#{player.name} は占い対象選択を取り消します。"
		end
		fortune_announce(str, player.num_id)
  elsif(player.sid == 4)
		if(t_name)
			str = "#{player.name} がスウィッチを押しました。"
		else
			str = "#{player.name} がスウィッチを引きました。"
		end
		possessed_announce(str, player.num_id)
	elsif(player.sid == 5 || player.sid == 16)
		if(t_name)
			str = "#{player.name} は #{t_name} を護衛します。"
		else
			str = "#{player.name} は護衛対象選択を取り消します。"
		end
		guard_announce(str, player.num_id)
	elsif(player.sid == 11)
		if(t_name)
			str = "#{player.name} は #{t_name} の中身を占います。"
		else
			str = "#{player.name} は中身占い対象選択を取り消します。"
		end
		fortune_id_announce(str, player.num_id)
	elsif(player.sid == 13)
		if(t_name)
			str = "#{player.name} は #{t_name} に愛を求めます。"
		else
			str = "#{player.name} は求愛対象選択を取り消します。"
		end
		cupid_announce(str, player.num_id)
	elsif(player.sid == 14)
		if(t_name)
			str = "#{player.name} は #{t_name} の邪魔をします。"
		else
			str = "#{player.name} は邪魔対象選択を取り消します。"
		end
		gammer_announce(str, player.num_id)
	end
end

def erbrun(file)
	ERB.new(File.open(file, "r:utf-8"){|f| f.read}).run(binding)
end

def erbres(file)
	ERB.new(File.open(file, "r:utf-8"){|f| f.read}).result(binding)
end
