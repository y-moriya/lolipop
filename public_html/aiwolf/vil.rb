# -*- coding: utf-8 -*-
require 'time'
require 'login'
require 'player'
require 'util'
require 'fileutils'

class Vil
	attr_reader :name, :pass, :date, :vid, :userid, :state, :chara, :num_char, :players
	attr_reader :night, :period, :night_period, :life_period
	attr_reader :victims, :executions
	attr_reader :composition, :skill_nums, :all_skill_num, :wide_comps
	attr_reader :char
	attr_reader :start_hour, :start_min, :entry_max, :entry_min, :dummy, :first_guard, :card, :open_vote, :hope_skill, :night_commit, :open_id, :open_skill, :death_defeat, :sayfull, :actfull
	attr_accessor :dummy, :possessed, :remainflag
	attr_accessor :say_cnt
	attr_accessor :num_id
	attr_accessor :upstart_time, :update_time, :upreset_time
	attr_accessor :tenko, :vildead_time

	def initialize(name, pass, vid, userid, period, night_period, life_period, composition, skill_nums, all_skill_num, wide_comps, char,
					start_hour, start_min, entry_max, entry_min, dummy, first_guard, card, open_vote, hope_skill, night_commit, open_id, open_skill,
          death_defeat, possessed, sayfull, actfull, remainflag)
		@name = name
    @pass = pass
		@userid = userid
		@vid = vid
		@date = 1
		@state = 0
		@char = char
    @possessed = possessed
    @sayfull = sayfull
    @actfull = actfull
    @remainflag = remainflag


		@period = period
		@night_period = night_period
		@life_period = life_period
		@night = false

		@start_hour = (start_hour && start_hour <= 23 && start_hour >= 0) ? start_hour : nil
		if (@start_hour)
			@start_min = (start_min && start_min <= 59 && start_min >= 0) ? start_min : 0

			time = Time.now
			time_all_sec = time.hour*60*60 + time.min*60 + time.sec
			start_all_sec = start_hour*60*60 + start_min*60

			@upstart_time = Time.now.to_i
			@upstart_time += start_all_sec - time_all_sec
			if (start_all_sec <= time_all_sec)
				@upstart_time += 24*60*60
			end
		end

		if (composition == CUSTOM)
			@entry_max = all_skill_num
			@entry_min = all_skill_num
		else
			comp = Composition.compositions[composition]

			@entry_max =
			if (entry_max > comp.max || entry_max < comp.min)
				comp.max
			else
				entry_max
			end

			@entry_min =
			if (entry_min < comp.min || entry_min > comp.max)
				comp.min
			else
				 entry_min
			end
		end

		@wide_comps = wide_comps
		@dummy = dummy
		@first_guard = first_guard
		@card = card
		@open_vote = open_vote
		@hope_skill = hope_skill
		@night_commit = night_commit
		@open_id = open_id
		@open_skill = open_skill
		@death_defeat = death_defeat

		@composition = composition
		@skill_nums = skill_nums
		@all_skill_num = all_skill_num

		@num_char = Array.new(Charset.charsets[char].char_names.size, 1)

		@players = Hash.new
		@victims = Array.new
		@executions = Array.new

		@say_cnt = Hash.new
		@say_cnt['say'] = 0
		@say_cnt['think'] = 0
		@say_cnt['groan'] = 0
		@say_cnt['whisper'] = 0
		@num_id = 2
    @vildead_time = Time.now + 60*60*24*7

		@tenko = -1
	end

	def edit(name, period, night_period, life_period, composition, skill_nums, all_skill_num, wide_comps,
				start_hour, start_min, entry_max, entry_min, first_guard, card, open_vote, hope_skill, night_commit, open_id, open_skill, death_defeat, possessed, sayfull, actfull, remainflag)
		@name = name
		@period = period
		@night_period = night_period
		@life_period = life_period
    @possessed = possessed
    @sayfull = sayfull
    @actfull = actfull
    @remainflag = remainflag

		@start_hour = (start_hour && start_hour <= 23 && start_hour >= 0) ? start_hour : nil

		if (@start_hour)
			@start_min = (start_min && start_min <= 59 && start_min >= 0) ? start_min : 0

			time = Time.now
			time_all_sec = time.hour*60*60 + time.min*60 + time.sec
			start_all_sec = start_hour*60*60 + start_min*60

			@upstart_time = Time.now.to_i
			@upstart_time += start_all_sec - time_all_sec
			if (start_all_sec <= time_all_sec)
				@upstart_time += 24*60*60
			end
		else
			@upstart_time = nil
			@start_hour = ''
			@start_min = ''
		end

		if (composition == CUSTOM)
			@entry_max = all_skill_num
			@entry_min = all_skill_num
		else
			comp = Composition.compositions[composition]

			@entry_max =
			if (entry_max > comp.max || entry_max < comp.min)
				comp.max
			else
				entry_max
			end

			@entry_min =
			if (entry_min < comp.min || entry_min > comp.max)
				comp.min
			else
				entry_min
			end
		end

		@wide_comps = wide_comps
		@first_guard = first_guard
		@card = card
		@open_vote = open_vote
		@hope_skill = hope_skill
		@night_commit = night_commit
		@open_id = open_id
		@open_skill = open_skill
		@death_defeat = death_defeat

		#@num_char = Array.new(Charset.charsets[char].char_names.size, 1)

		@composition = composition
		@skill_nums = skill_nums
		@all_skill_num = all_skill_num

		#@userid = "General" if (@vid == 900)

	end

	def add_player(player)
		@players[player.userid] = player

		vldb = PStore.new('db/vil.db')
		vldb.transaction do
			vil = vldb["root#{@vid}"]
			vil['player_num'] = @players.size
		end
	end

	def player(login)
		if (!players[login.userid])
			return nil
		end
		return players[login.userid]

	end

	def prv(type, cnt, player, msg)
		name = player.name
		pid = "#{Charset.charsets[@char].file_name}#{two(player.pid)}"
		id = player.num_id
		link = "vid=#{@vid}&id=#{id}&date=#{@date}"
		mark = ''
		msg.gsub!(/(&gt;&gt;(\d+):([*+-]?)(\d+)|&gt;&gt;([*+-]?)(\d+))/) do |m|
			say_ref(m, type, $2, $3, $4, $5, $6)
		end
		if (cnt)
			s = %Q(<a name="#{type}#{cnt}"></a><a href="##{type}#{cnt}">#{mark}#{cnt}</a> )
		end
		day = Time.now
		timestr = day.strftime("%Y/%m/%d %X")
		typehead = 'say'
		s += %Q(<a href="?#{link}" target="_blank">#{name}</a> <span class="time">#{timestr}</span>)
		s2 = %Q(<!--#{typehead}#{id}--><table class="message"><tr><td width="100" rowspan="2"><img src="img/#{pid}.png"></td><td colspan="2">#{s}</td></tr><tr><td valign="top"><div class="mes_#{type}"></div></td><td width="584" valign="top"><div class="mes_#{type}_body0"><div class="mes_#{type}_body1">#{msg}</div></div></td></tr></table>\n)
		s2
	end

	def say(type, cnt, player, msg, userid)
		if(player)
			name = player.name
			name += " (#{userid})" if (state == 2 || @open_id)
			pid = "#{Charset.charsets[@char].file_name}#{two(player.pid)}"
			id = player.num_id
			player.say_cnt += 1 if (type == 'say')
			link = "vid=#{@vid}&id=#{id}&date=#{@date}"

		else
			name ="#{userid}"
			pid = Charset.charsets[@char].spectator_filename
			link = "cmd=user&uid=#{CGI.escape(userid)}"
		end

		mark =
			if (type == 'whisper')
				'*'
			elsif (type == 'think')
				'-'
			elsif (type == 'groan')
				'+'
			else
				''
			end

		if(@state == 0 && @tenko != -1 && player && player.tenko == -1 && mark == '')
			@tenko = @tenko + 1
			player.tenko = @tenko
		end

		#name.gsub!(/a/, %Q(<span class="vote">a</span>))
		#msg.misakura!
		#msg.fortune!
		msg.vil_url!
		msg.gsub!(/(&gt;&gt;(\d+):([*+-]?)(\d+)|&gt;&gt;([*+-]?)(\d+))/) do |m|
			say_ref(m, type, $2, $3, $4, $5, $6)
		end

		if (cnt)
			s = %Q(<a name="#{type}#{cnt}"></a><a href="##{type}#{cnt}">#{mark}#{cnt}</a> )
		end

		day = Time.now
		timestr = day.strftime("%Y/%m/%d %X")

		typehead = (@night && type == 'whisper') ? 'whisperhowl' : type

		s += %Q(<a href="?#{link}" target="_blank">#{name}</a> <span class="time">#{timestr}</span>)
		s2 = %Q(<!--#{typehead}#{id}--><table class="message"><tr><td width="100" rowspan="2"><img src="img/#{pid}.png"></td><td colspan="2">#{s}</td></tr><tr><td valign="top"><div class="mes_#{type}"></div></td><td width="584" valign="top"><div class="mes_#{type}_body0"><div class="mes_#{type}_body1">#{msg}</div></div></td></tr></table>\n)
		s2
	end

	def say_action(player, msg)
		msg.gsub!(/(&gt;&gt;(\d+):([*+-]?)(\d+)|&gt;&gt;([*+-]?)(\d+))/) do |m|
			say_ref(m, type, $2, $3, $4, $5, $6)
		end
		day = Time.now
		timestr = day.strftime("%Y/%m/%d %X")
		s = "#{player.name}" + msg + %Q( <span class="act_time">#{timestr}</span>)
		act_announce(s, player.num_id)
	end

	def say_ref(m, my_type, v2, v3, v4, v5, v6)
		if (v2)
			colon = true
			type = v3
			dt = v2
			nm = v4
		else
			colon = false
			type = v5
			dt = @date
			nm = v6
		end

		t =
			if (type == '*')
				'whisper'
			elsif (type == '-')
				'think'
			elsif (type == '+')
				'groan'
			else
				'say'
			end

		pop = ''
		logfile = "db/log#{(@vid - 1) / 100}/#{@vid}_#{dt}.html"
		if (@state == 2 || t == 'say' || (t == 'groan' && my_type == 'groan') || (t == 'whisper' && my_type == 'whisper'))
			if (FileTest.exist?(logfile))
				File.open(logfile, "r:utf-8") do |ifile|
					reg = /<img src="(img\/[^\.]+).png"><\/td><td colspan="2"><a name="#{t}#{nm}"><\/a><a href="##{t}#{nm}">[*+-]?#{nm}<\/a> <a href="\?[^"]+" target="_blank">([^<]*)<\/a> <span class="time">([^<]+)<\/span><\/td><\/tr><tr><td><div class="mes_[^_]+"><\/div><\/td><td width="464"><div class="mes_[^_]+_body0"><div class="mes_[^_]+_body1">(.*)$/
					ifile.each do |line|
						if (reg =~ line)
							rpid = $1
							rname = $2
							rtime = $3
							rmsg = $4
							rmsg.gsub!(/'/, '&apos;')
							rmsg.gsub!(/&/, '&amp;')
							rmsg.gsub!(/<br>/, '&lt;br&gt;')
							rmsg.gsub!(/<\/div>/, '')
							rmsg.gsub!(/<\/td>/, '')
							rmsg.gsub!(/<\/tr>/, '')
							rmsg.gsub!(/<\/table>/, '')
							rmsg.gsub!(/<a [^>]+>([^<]+)<\/a>/) {"&lt;span class=&quot;popsay&quot;&gt;#{$1}&lt;/span&gt;"}
							if(/<div class="loud">/ =~ rmsg)
								rmsg.gsub!(/<div class="loud">/, '&lt;div class=&quot;loud&quot;&gt;')
								rmsg += "&lt;/div&gt;"
							end
							if(/<div class="small_voice">/ =~ rmsg)
								rmsg.gsub!(/<div class="small_voice">/, '&lt;div class=&quot;small_voice&quot;&gt;')
								rmsg += "&lt;/div&gt;"
							end
							pop = %Q( onmouseover="popup('#{rpid}', '#{type}#{nm} #{rname}', '#{rtime}', '#{t}', '#{rmsg}', event);" onmouseout="popdown();")
							break
						end
					end
				end
			end
		end
		%Q(<a class="say" href="?vid=#{@vid}&date=#{dt}&log=all##{t}#{nm}"#{pop}>#{m}</a>)
	end

	def events
		@events ||= []
	end

	def addlog(msg)
		File.open("db/log#{(@vid - 1) / 100}/#{@vid}_#{@date}.html", 'a') do |of|
			of.flock(File::LOCK_EX)
			of.print(msg)
		end

		begin
			record_event(msg)
		rescue => e
			STDERR.puts "[addlog Error] #{e.class}: #{e.message}"
			STDERR.puts e.backtrace.join("\n")
		end
	end

	def record_event(msg)
		@events ||= []
		now_str = Time.now.strftime("%Y/%m/%d %H:%M:%S")

		strip_html = lambda do |html|
			return "" if html.nil?
			text = html.gsub(/<br\s*\/?>/i, "\n").gsub(/<[^>]+>/, '')
			text.gsub!(/&lt;/, '<')
			text.gsub!(/&gt;/, '>')
			text.gsub!(/&amp;/, '&')
			text.gsub!(/&quot;/, '"')
			text.strip
		end

		matched = false

		# 1. Normal chat messages, thinks, whispers, groans, etc.
		msg.scan(/<!--(say|think|whisper|groan|fanatic|spirit|sprit|whisperhowl)(\d*)-->\s*<table class="message">.*?(?:<a name="[^"]+"><\/a><a href="[^"]+">[*+-]?(\d+)<\/a>\s*)?<a href="[^"]+" target="_blank">(.*?)<\/a>.*?<span class="time">(.*?)<\/span>.*?<div class="mes_(?:say|think|whisper|groan|fanatic|spirit|sprit|whisperhowl)_body1">(.*?)<\/div>.*?<\/table>/m) do |type_code, speaker_id_str, count_str, speaker, time_str, content_html|
			matched = true
			next_id = @events.empty? ? 1 : @events.last[:id] + 1
			speaker_id = (speaker_id_str.nil? || speaker_id_str.empty?) ? nil : speaker_id_str.to_i
			type_code = 'spirit' if type_code == 'sprit'
			avatar = nil
			if $& =~ /img src=["']img\/([a-zA-Z0-9_-]+)\.png["']/
				avatar = $1
			end
			count = (count_str.nil? || count_str.empty?) ? nil : count_str.to_i
			@events << {
				id: next_id,
				type: 'message',
				type_code: type_code,
				speaker_id: speaker_id,
				speaker: speaker,
				avatar: avatar,
				time: time_str,
				content: strip_html.call(content_html),
				day: @date,
				count: count
			}
			STDERR.puts "[record_event] Recorded message: #{strip_html.call(content_html)} (count: #{count})"
		end

		# 1b. Masked howl
		msg.scan(/<table class="message">.*?<td colspan="2" class="howl">狼の遠吠え<\/td>.*?<div class="mes_whisper_body1">(.*?)<\/div>.*?<\/table>/m) do |content_html|
			matched = true
			next_id = @events.empty? ? 1 : @events.last[:id] + 1
			avatar = nil
			if $& =~ /img src=["']img\/([a-zA-Z0-9_-]+)\.png["']/
				avatar = $1
			end
			@events << {
				id: next_id,
				type: 'message',
				type_code: 'whisperhowl',
				speaker_id: nil,
				speaker: 'システム',
				avatar: avatar,
				time: now_str,
				content: "狼の遠吠え: " + strip_html.call(content_html),
				day: @date
			}
			STDERR.puts "[record_event] Recorded howl: #{strip_html.call(content_html)}"
		end

		# 2. System announcements
		msg.scan(/<!--(say|think|whisper|groan|fanatic|spirit|sprit|whisperhowl)?(\d*)-->\s*<div class="announce.*?">(.*?)<\/div>/m) do |tag_type, target_id_str, content_html|
			matched = true
			next_id = @events.empty? ? 1 : @events.last[:id] + 1
			target_id = (target_id_str.nil? || target_id_str.empty?) ? nil : target_id_str.to_i
			tag_type = 'spirit' if tag_type == 'sprit'
			event_type_code = if (tag_type.nil? || tag_type == 'say') && target_id.nil?
				'announce'
			else
				tag_type || 'announce'
			end

			@events << {
				id: next_id,
				type: 'system',
				type_code: event_type_code,
				speaker_id: target_id,
				time: now_str,
				content: strip_html.call(content_html),
				day: @date
			}
			STDERR.puts "[record_event] Recorded announce: #{strip_html.call(content_html)}"
		end

		# 3. Time advances or state changes
		msg.scan(/<(?:div|span) class="(?:time_announce|alllog_announce)">(.*?)<\/(?:div|span)>/m) do |content_html|
			matched = true
			next_id = @events.empty? ? 1 : @events.last[:id] + 1
			@events << {
				id: next_id,
				type: 'state_change',
				type_code: 'time',
				time: now_str,
				content: strip_html.call(content_html),
				day: @date
			}
			STDERR.puts "[record_event] Recorded time change: #{strip_html.call(content_html)}"
		end

		unless matched
			STDERR.puts "[record_event] Unmatched message pattern: #{msg[0..60]}..."
		end
	end

	def display_skill
		s = ''
		j = 0
		for i in 0...@skill_nums.size do
			@skill_nums[i].times do
				s += Skill.skills[i].sname
				j += 1
			end
		end
		if (@dummy)
			s.gsub!(/^村/, "ダ")
		end
		"#{j}人：#{s}"
	end

	def display_composition(comp_i)
		str =
			if(comp_i == WIDE_CUSTOM)
				wide_display
			else
				Composition.display(comp_i)
			end
		str.sub!(/(<br>)(#{@players.size}人)/) do |m|
			%Q(#{$1}<span class="flash">#{$2}</span>)
		end
		str.sub!(/^(#{@players.size}人)/) do |m|
			%Q(<span class="flash">#{$1}</span>)
		end
		if (@dummy)
			str.gsub!(/：村/, "：ダ")
		end
		str
	end

	def wide_display
		s = ''
		comp = Composition.compositions[@composition]
		for i in comp.min..comp.max do
			if(@wide_comps[i])
				n =
					if(i < 10)
						"#{i}人 ："
					else
						"#{i}人："
					end
				s += n + @wide_comps[i] + "<br>"
			end
		end
		s
	end

	def plain_wide_display
		s = ''
		comp = Composition.compositions[@composition]
		for i in comp.min..comp.max do
			if(@wide_comps[i])
				s += @wide_comps[i] + "&#13;"
			end
		end
		s
	end

	def set_skill
		a = Array.new
		comp = Composition.compositions[@composition]
		num_p = pids.size

		if (@composition == CUSTOM)
			if (@all_skill_num == num_p)
				return true
			else
				return false
			end
		elsif (@composition == POSTING)
			return false if(num_p < comp.min || num_p > comp.max)
			pscompdb = PStore.new('db/pscomp.db')
			pscompdb.transaction do
				return false if (!pscompdb.root?(num_p))
				psco =
				if (@dummy)
					 pscompdb[num_p].select { |c| /^村/ =~ c['comp'] }
				else
					pscompdb[num_p]
				end

				return false if (psco.size == 0)
				r = psco[rand(psco.size).to_i]
				for i in 0...Skill.skills.size do
					n = r['comp'].count(Skill.skills[i].sname)
					a.push(n)
				end
				@skill_nums = a
			end
			return true
		elsif (@composition == WIDE_CUSTOM)
			return false if(num_p < comp.min || num_p > comp.max)
			return false if(!@wide_comps[num_p])
			for i in 0...Skill.skills.size do
				n = @wide_comps[num_p].count(Skill.skills[i].sname)
				a.push(n)
			end
			@skill_nums = a
			return true
    elsif (@composition == RANDOM)
			return false if(num_p < comp.min || num_p > comp.max)
      @skill_nums = set_random(comp, num_p)
      return true
		else
			return false if(num_p < comp.min || num_p > comp.max)
			for i in 0...Skill.skills.size do
				n = comp.list[num_p].count(Skill.skills[i].sname)
				a.push(n)
			end
			@skill_nums = a
			return true
		end
	end

	def announce_composition
		s = 'どうやらこの村には'
		for i in 0...@skill_nums.size do
			n = @skill_nums[i]
			s += "、#{Skill.skills[i].name}が#{n}人" if (n !=0)
		end
		s += 'いるようです。'
		addlog(announce(s))
	end

  def announce_random
    s = RANDOM_MSG
    addlog(announce(s))
  end

  def set_random(comp, num_p)
    a = Array.new(Skill.skills.size, 0)
    for i in 0...Skill.skills.size do
      n = comp.list.count(Skill.skills[i].sname)
      a[i] += n
      num_p -= n
    end
    for i in 1..num_p do
      j = rand(Skill.skills.size)
      while j == 0
        j = rand(Skill.skills.size)
      end
      a[j] += 1
    end
    return a
  end

	def announce_firstsid
		str = ''
		s = "この村に潜む#{Skill.skills[1].name}は"
		@players.values.select { |p| p.sid == 1 }.each do |p|
			s += "、#{p.name}"
		end
		s += ' です。'
		str += fanatic_announce(s)

		ps = @players.values.select { |p| p.sid == 6 }
		if (ps.size == 1)
			str += free_announce("あなたは凄い共有者です。凄すぎて相方はいません。", ps[0].num_id)
		elsif (ps.size > 1)
			ps.each do |p|
				s_free = ''
				ps.each do |m|
					if (p != m)
						s_free += "、#{m.name}"
					end
				end
				str += free_announce("あなたと心を共有するのは#{s_free} です。", p.num_id)
			end
		end
		ps = @players.values.select { |p| p.sid == 10 }
		i = 1
		while (ps.size > 0)
			p = ps[rand(ps.size).to_i]
			str += stigmata_announce("あなたは 聖痕者#{i} です。", p.num_id)
			ps.delete(p)
			i += 1
		end
		addlog(str)
	end

	def up_mirror
		return if(!set_skill)
		lefts = @skill_nums.clone
    if @composition == RANDOM && !DEBUG
      announce_random
    else
      announce_composition
    end

		if (!hope_skill)
			@players.each_value do |p|
				p.sid = -1
			end
		end
		ps = @players.values.select { |p| p.sid == -2 }
		for i in 0...ps.size
			r = rand(lefts.size).to_i
			r = rand(lefts.size).to_i while (lefts[r] == 0)
			ps[i].sid = r
		end

		lefts.each_index do |i|
			if (lefts[i] == 0)
				@players.values.select { |p| p.sid == i }.each do |p|
					p.sid = -1
				end
	        	next
			end

			ps = @players.values.select { |p| p.sid == i }
			if (ps.size > lefts[i])
				for j in 0...(ps.size - lefts[i])
					r = rand(ps.size).to_i
					r = rand(ps.size).to_i while (ps[r].sid == -1)
					ps[r].sid = -1
				end
				lefts[i] = 0
			else
				lefts[i] -= ps.size
			end
		end
		ps = @players.values.select { |p| p.sid == -1 }
		shrink_cnt = 0
		lefts.each do |c|
			shrink_cnt += c
		end
		shrink_cnt -= ps.size

		if (shrink_cnt != 0)
			addlog(announce("なんかエラーのせいで役職が人数より多い予感、ランダムで#{shrink_cnt}人分削ります。"))
		end

		for i in 0...shrink_cnt
			r = rand(lefts.size).to_i
			r = rand(lefts.size).to_i while (lefts[r] == 0)
			lefts[r] -= 1
		end
		if (ps.size > 0)
	      	Skill.skills.each_index do |i|
				next if (lefts[i] == 0)

				for j in 0...lefts[i]
					r = rand(ps.size).to_i
					r = rand(ps.size).to_i while (ps[r].sid != -1)
					ps[r].sid = i
				end
			end
		end
		if (dummy && player_p(1).sid != 0 && @composition != RANDOM) || (@composition == RANDOM && player_p(1).sid == 1)
			ps = pids_s(0)
			p = ps[rand(ps.size).to_i]
			p.sid = player_p(1).sid
			player_p(1).sid = 0
		end
		announce_firstsid
	end

	def up_lifetime
		if(@life_period)
			@update_time += @life_period * pids.size
		end
	end

	def up_uptime(period = @period)
		now = Time.now.to_i
		if (@update_time && @update_time < now)
			@update_time += period * 60
		else
			@update_time = now + period * 60
		end
		if (period >= ALL_DAY_PERIOD && @upstart_time)
			dt = Time.at(@update_time)
			st = Time.at(@upstart_time)
			d_time = st.hour*60*60 + st.min*60 + st.sec - (dt.hour*60*60 + dt.min*60 + dt.sec)
			@update_time += d_time
			@update_time += ALL_DAY_PERIOD * 60 if (d_time < 0)
		end
	end

	def up_upreset_time
		now = Time.now.to_i
		return if (@period < ALL_DAY_PERIOD)
		if (@upreset_time && @upreset_time < now)
			@upreset_time += ALL_DAY_PERIOD * 60
		else
			return if (!@upstart_time)
			if (@upstart_time < now)
				@upreset_time = @upstart_time + ALL_DAY_PERIOD * 60
			else
				@upreset_time = @upstart_time
			end
		end
		up_resetremain if @remainflag
	end

	def pids
		@players.values.select do |v|
			v.dead != 1
		end.sort do |x, y|
			x.num_id <=> y.num_id
		end
	end

	def pids_judge
		@players.values.select do |v|
			v.dead == 0
		end.sort do |x, y|
			x.num_id <=> y.num_id
		end
	end

	def survivors
		@players.values.select do |p|
			@victims.all?{|v| v != p} && @executions.all?{|e| e != p}
		end.sort do |x, y|
			x.num_id <=> y.num_id
		end
	end

	def pids_s(sid)
		pids.select do |p|
			p.sid == sid
		end
	end

	def pids_s_judge(sid)
		pids_judge.select do |p|
			p.sid == sid
		end
	end

	def skill_pids
		a = Array.new
		a = pids_s_judge(1) + pids_s_judge(2) + pids_s_judge(11) + pids_s_judge(14)
		a += pids_s_judge(5) + pids_s_judge(16) if (can_guard(@date + 1))
		a += pids_s_judge(12) + pids_s_judge(13) if (can_cupid(@date + 1))
    a += pids_s_judge(4) if @possessed
		a
	end

	def player_p(num_id)
		p = players.find do |p|
			p[1].num_id == num_id
		end
		return p[1] if p
	end

	def up_follow_lover
		ps = @players.values.select { |p| p.dead == 0 && p.lovers.size > 0 }.sort { |x, y|x.num_id <=> y.num_id }
		while(!ps.empty?)
			pf = ps.find { |p| p.lovers.any?{|l| l.dead != 0} }
			return if (!pf)
			pl = pf.lovers.find { |l| l.dead != 0}
			pf.dead = 3
			@victims.push(pf)
			msg = "#{pf.name} は悲しみにくれて、#{pl.name} の後を追いました。"
			ps.delete(pf)
			addlog(cupid_announce(msg))
		end
	end

	def up_cupid
		return if (pids.size < 2)
		pids_s_judge(12).each do |p|
			r = ''
			if (p.target == -1 || p.target2 == -1)
				p.target = pids[rand(pids.size).to_i].num_id
				p.target2 = pids[rand(pids.size).to_i].num_id
      			p.target2 = pids[rand(pids.size).to_i].num_id while (p.target2 == p.target)
				r = '(ランダム)'
			end
			t = player_p(p.target)
			t2 = player_p(p.target2)
			t.lovers.push(t2)
			t2.lovers.push(t)
			t.lovers.sort { |x, y|x.num_id <=> y.num_id }
			t2.lovers.sort { |x, y|x.num_id <=> y.num_id }
			msg = "#{p.name} は愛の矢を撃ちました。"
			msg += r
			msg += "<br>#{t.name} と #{t2.name} は恋に落ちました。"
			addlog(cupid_announce(msg, p.num_id))
		end
		pids_s_judge(13).each do |p|
			r = ''
			if (p.target == -1)
				p.target = pids[rand(pids.size).to_i].num_id
      			p.target = pids[rand(pids.size).to_i].num_id while (p.target == p.num_id)
				r = '(ランダム)'
			end
			t = player_p(p.target)
			t2 = player_p(p.num_id)
			t.lovers.push(t2)
			t2.lovers.push(t)
			t.lovers.sort { |x, y|x.num_id <=> y.num_id }
			t2.lovers.sort { |x, y|x.num_id <=> y.num_id }
			msg = "#{p.name} は #{t.name} に愛を求めました。"
			msg += r
			msg += "<br>#{t2.name} と #{t.name} は恋に落ちました。"
			addlog(cupid_announce(msg, p.num_id))
		end
	end

	def up_fortune
		return if (pids.size < 2)
		all_gam = Array.new
		pids_s_judge(14).each do |p|
			r = ''
			if (p.target == -1)
				p.target = pids[rand(pids.size).to_i].num_id
      			p.target = pids[rand(pids.size).to_i].num_id while (p.target == p.num_id)
				r = '(ランダム)'
			end
			gam = player_p(p.target)
			all_gam.push(gam)
			msg = "#{p.name} は、#{gam.name} の邪魔をしています。"
			msg += r
      		addlog(gammer_announce(msg, p.num_id))
		end
		pids_s_judge(2).each do |p|
			r = ''
			if (p.target == -1)
				p.target = pids[rand(pids.size).to_i].num_id
      			p.target = pids[rand(pids.size).to_i].num_id while (p.target == p.num_id)
				r = '(ランダム)'
			end
			t = player_p(p.target)
			res =
				if (t.sid == 1)
					Skill.skills[1].name
				else
					"人間"
				end
			msg = "#{p.name} は、#{t.name} を占いました。"
			msg += r
			if (all_gam.all? {|g| g != p})
				t.fortune_t[p] = @date - 1
				msg += "<br>#{t.name} は #{res}のようです。"
				if (t.dead == 0 && t.sid == 7)
					t.dead = 2
				end
			else
				msg += "<br>しかし何かの力に邪魔されました。"
			end
      		addlog(fortune_announce(msg, p.num_id))
		end
		pids_s_judge(11).each do |p|
			r = ''
			if (p.target == -1)
				p.target = pids[rand(pids.size).to_i].num_id
      			p.target = pids[rand(pids.size).to_i].num_id while (p.target == p.num_id)
				r = '(ランダム)'
			end
			t = player_p(p.target)
			msg = "#{p.name} は、#{t.name} の中身を占いました。"
			msg += r
			if (all_gam.all? {|g| g != p})
				t.fortune_id_t[p] = @date - 1
				msg += "<br>#{t.name} の中身は #{t.userid} のようです。"
			else
				msg += "<br>しかし何かの力に邪魔されました。"
			end
      		addlog(fortune_id_announce(msg, p.num_id))
		end
    end

	def can_guard(date)
		if (@card)
			!((@dummy || !@first_guard) && date <= 2)
		else
			!((@dummy || !@first_guard) && date <= 3)
		end
	end

	def can_cupid(date)
		if (@card)
			(date == 2)
		else
			(date == 3)
		end
	end

	def attack_dummy(date)
		if (@card)
			(@dummy && date <= 2)
		else
			(@dummy && date <= 3)
		end
	end

	def up_attack
		wolfs = pids_s_judge(1).select { |p| p.target != -1 }
		return if (wolfs.size >= pids.size)
		t = nil
		w = nil
		if (wolfs.size > 0)
			w = wolfs[rand(wolfs.size).to_i]
			if	(attack_dummy(@date))
				t = player_p(1)
			else
				t = player_p(w.target)
			end
			s =
				if ( pids_s_judge(1).size > 1)
					' 達'
				else
					' '
				end
			addlog(whisper_announce("#{w.name}#{s}は、#{t.name} を襲撃します。"))
		else
			r = ''
			if (attack_dummy(@date))
				t = player_p(1)
			else
				r = '(ランダム)'
				t = pids[rand(pids.size).to_i]
	      		t = pids[rand(pids.size).to_i] while (t.sid == 1)
			end
			s =
				if ( pids_s_judge(1).size > 1)
					"#{Skill.skills[1].name}達"
				else
					"#{pids_s_judge(1)[0].name} "
				end
			addlog(whisper_announce("#{s}は、#{t.name} を襲撃します。#{r}"))
		end

		all_g = Array.new
		if (can_guard(@date))
			[5, 16].each do |sid|
				(pids_s_judge(sid)).each do |p|
					r = ''
					if (p.target == -1)
						p.target = pids[rand(pids.size).to_i].num_id
		      			p.target = pids[rand(pids.size).to_i].num_id while (p.target == p.num_id)
						r = '(ランダム)'
					end
					g = player_p(p.target)
					if (g.guard_t.key?(p))
						msg = "#{p.name} は、#{g.name} をもう護衛しません。"
						msg += r
					else
						all_g.push(g)
						msg = "#{p.name} は、#{g.name} を護衛しています。"
						msg += r
					end
		      		addlog(guard_announce(msg, p.num_id))
				end
			end
		end

		if (all_g.all? {|g| g != t} && t.dead == 0 && t.sid != 7)
			t.dead = 2
		end

		if (can_guard(@date))
			ps = @players.values.select { |p| p.dead == 2 }
			if (ps.size == 0)
				pids_s_judge(16).each do |p|
					g_t = player_p(p.target)
					g_t.guard_t[p] = @date - 1
				end
			end
		end
    end

	def up_gameover
		wcnt = pids_s_judge(1).size
		ycnt = pids_s_judge(7).size
		lcnt = pids_judge.select { |p| p.lovers.size != 0 }.size
		pcnt = pids_judge.size - ycnt
		if (wcnt == 0 || (wcnt * 2) >= pcnt)
			if (lcnt > 0)
				addlog(announce(LOVE_WIN))
				addlog(win_announce("恋人の勝利です！"))
				@players.values.select { |p| p.lovers.size != 0 || Skill.skills[p.sid].position == '恋人' }.each do |p|
					p.win = 0
				end
			else
				if(ycnt == 0)
					if (wcnt == 0)
						addlog(announce(FOLK_WIN))
						addlog(win_announce("村人の勝利です！"))
						@players.values.select { |p| p.lovers.size == 0 && Skill.skills[p.sid].position == '村人' }.each do |p|
							p.win = 0
						end
					else
						addlog(announce(WOLF_WIN))
						addlog(win_announce("#{Skill.skills[1].name}の勝利です！"))
						@players.values.select { |p| p.lovers.size == 0 && Skill.skills[p.sid].position == '人狼' }.each do |p|
							p.win = 0
						end
					end
				else
					if (wcnt == 0)
						addlog(announce(YOKO_WIN_F))
					else
						addlog(announce(YOKO_WIN_W))
					end
					addlog(win_announce("妖魔の勝利です！"))
					@players.values.select { |p| Skill.skills[p.sid].position == '妖魔' }.each do |p|
						p.win = 0
					end
				end

			if(@death_defeat)
				@players.values.select { |p| p.dead > 0 }.each do |p|
					p.win = -1
				end
			end

			end
			change_state
			@night = false
			up_record
			if (DEBUG_SHORT)
				up_uptime(1)
			else
				up_uptime(7*24*60)
			end
			@players.each_value do |p|
				p.dead = 0
			end
			return true
		end
		return false
	end

	def up_sudden_death
		return if (@period < LONG)
		pids.each do |p|
			if (p.say_cnt == 0)
				p.dead = 3
				@executions.push(p)
				addlog(execution_announce("#{p.name} が突然死しました。"))
				res =
					if (p.sid == 1)
						#{Skill.skills[1].name}
					else
						"人間"
					end
				addlog(spirit_announce("#{p.name} は #{res}だったようです。"))
			end
		end
	end

	def up_vote
		votes = Hash.new
		max = 0

		s = ''
		s2 = ''
		pids_judge.each do |p|
			if (p.vote == -1)
				p.vote = pids[rand(pids.size).to_i].num_id
				p.vote = pids[rand(pids.size).to_i].num_id while (p.vote == p.num_id)
				t = player_p(p.vote)
				r = "#{p.name} が #{t.name} に投票しました。(ランダム)"
				addlog(setvote(p.num_id, r))
			end

			t = player_p(p.vote)
			s += "<tr><td>#{p.name}</td><td>は</td><td>#{t.name}</td><td>に投票しました。</td></tr>"

			votes[t] = votes[t].to_i + 1
			max = votes[t] if (votes[t] > max)
		end

		if (!votes.empty?)
			if (@open_vote)
				str = announce("<table class=\"vote_t\">#{s}</table>")
			else
				str = secret_announce("<table class=\"vote_t\">#{s}</table>")
				pids.each do |p|
					next if (votes[p].to_i == 0)
					s2 += "<tr><td>#{p.name}</td><td>に、#{votes[p]}人が投票しました。</td></tr>"
				end
				str = str + announce("<table class=\"vote_t\">#{s2}</table>")
			end

			picked = votes.select { |k, v| v == max }
			result = picked.to_a[rand(picked.size).to_i][0]
			addlog(str)
			if (result.dead == 0)
				result.dead = 3
				@executions.push(result)
				addlog(execution_announce("投票の結果、#{result.name} が処刑されました。"))
				res =
					if (result.sid == 1)
						Skill.skills[1].name
					else
						"人間"
					end
				addlog(spirit_announce("#{result.name} は #{res}だったようです。"))
			end
		end
	end

	def change_state
		@state += 1
		vldb = PStore.new('db/vil.db')
		vldb.transaction do
			vild = vldb["root#{@vid}"]
			vild['state'] = @state
		end
	end

  def vil_dead
    @state = 3
    vldb = PStore.new('db/vil.db')
    vldb.transaction do
      vild = vldb["root#{@vid}"]
      vild['state'] = @state
    end
  end

	def up_reset_vote
		pids.each do |p|
			p.vote = -1
		end
	end

	def up_reset_target
		pids.each do |p|
			p.target = -1
		end
	end

	def up_reset_deathtarget
		pids.each do |p|
			next if (p.target == -1)
      next if (p.sid == 4)
			t = player_p(p.target)
			p.target = -1 if (t.dead != 0)
		end
	end

	def up_resetcnt
		@say_cnt['say'] = 0
		@say_cnt['think'] = 0
		@say_cnt['groan'] = 0
		@say_cnt['whisper'] = 0

		pids.each do |p|
			p.say_cnt = 0
		end
		up_resetremain
	end

	def up_resetremain
		return if (@period < LONG)
		pids.each do |p|
			p.say_remain = @sayfull
			p.action_remain = @actfull
		end
	end

	def up_death
		ps = @players.values.select { |p| p.dead == 2 }
		if (ps.size == 0)
			addlog(safety_announce("今日は犠牲者がいないようだ。#{Skill.skills[1].name}は襲撃を失敗したのだろうか。"))
			if ((@card && @date == 2) || (!@card && @date == 3))
				addlog(announce("長く不安な夜が明けました。狼の遠吠えと、足音を聞いた者も何人かいます。<br>話し合いの結果、村人達は#{Skill.skills[1].name}を処刑するために投票を行うことにしました。"))
			end
		else
			while (ps.size > 0)
				p = ps[rand(ps.size).to_i]
				p.dead = 1
				@victims.push(p)
				addlog(victim_announce("#{p.name} が無残な姿で発見されました。"))
				ps.delete(p)
			end
			if ((@card && @date == 2) || (!@card && @date == 3))
				if(@death_defeat)
					str = "或る村で、明らかに「食い散らかされた」と解る、おぞましいダニエル（固定）の死体が見つかりました。<br>人狼伝説なんて存在しないこの村では、村に殺人者―――人食いが現れたのだと、すぐに理解しました。<br>このままでは、村は人食いに食い尽くされて滅びてしまうでしょう。<br><br>だから、村人達は、『自らが生き残る為に』、同じ村人達を疑い……多数決で、民主的に疑わしきを罰して行くことにしたのです。<br>犠牲者が出なくなる、その時まで。"
				else
					str = "ついに犠牲者が出てしまいました。やはり人狼はいたのです。<br>話し合いの結果、村人達は人狼を処刑するために投票を行うことにしました。"
				end
				addlog(announce(str))
			end
		end
	end

	def day_update
		@night = true
		up_uptime(@night_period)
		up_sudden_death if (@date > 1)
		if ((@card && @date > 1) || @date > 2)
			up_vote
		end
		up_follow_lover
		@players.values.select { |p| p.dead == 3 }.each do |p|
			p.dead = 1
		end
		up_reset_vote
		up_reset_deathtarget
		return if (up_gameover)
		up_lifetime
		addlog(announce("夜になりました。<br>村人達は家に鍵をかけ、夜が明けるのを待っています。"))
	end

	def night_update
		@night = false
		up_uptime
		@date += 1

		if ((@card && @date == 2) || (!@card && @date == 3))
			up_cupid
		end
		up_fortune
		up_attack
		up_death
		up_follow_lover
		@players.values.select { |p| p.dead == 3 }.each do |p|
			p.dead = 1
		end
		up_reset_vote
		up_reset_target
		up_resetcnt

    	return if (up_gameover)

		if (DEBUG)
			s = '現在の生存者は'
			pids.each do |p|
				s += ", #{p.name}"
			end
			s += "の#{pids.size}人です。テキトーに頑張りましょう。"
			addlog(announce(s))
		end
	end

	def allday_update
		up_uptime
		@date += 1
		up_sudden_death if (@date > 2)
		if (@date > 3)
			up_vote
		end
		if (!@card && @date == 3)
			up_cupid
		end
		up_follow_lover
		up_resetcnt
		return if (up_gameover)
		up_fortune
		up_attack
		up_death
		up_follow_lover
		return if (up_gameover)
		@players.values.select { |p| p.dead == 3 }.each do |p|
			p.dead = 1
		end
		up_reset_vote
		up_reset_target
		up_resetcnt
	end

	def up_record
		vldb = PStore.new('db/vil.db')
		sname = vldb.transaction do
			vild = vldb["root#{@vid}"]
			vild['sname']
		end
		recorddb = PStore.new('db/record.db')
		recorddb.transaction do
			num = @players.size
			@players.each_value do |p|
				rec = Hash.new
				rec['vid'] = @vid
				rec['sname'] = sname
				rec['num'] = num
				rec['composition'] = @composition
				rec['p_name'] = p.name
				rec['win'] = p.win
				rec['sid'] = p.sid
				rec['love'] = (p.lovers.size == 0) ? false : true

				if (!recorddb.root?(p.userid))
					recorddb[p.userid] = Array.new
				end
				recorddb[p.userid].push(rec)
			end
		end
	end

	def up_char_list(players, date, type)
		s = ''
		players.each do |p|
			f_name = "#{Charset.charsets[@char].file_name}_s#{two(p.pid)}"
			s += %Q(<tr><td width="76" height="98"><img src="../img/#{f_name}.png"></td>)
			s += %Q(<td>#{p.name})
			s += %Q(<br>ID: <a href="../?cmd=user&uid=#{CGI.escape(p.userid)}">#{p.userid}</a><br>#{Skill.skills[p.sid].name})
			if (p.lovers.size != 0)
				s += %Q(<span class="cupid">(恋人)</span>)
			end
			s += "</td></tr>"
		end
		s
	end

	def do_end
		all_type = ["say", "whisper", "groan", "think", "all"]
		log = Array.new
		unlinks = Array.new
		@log_fnames = Array.new
		for date in 1..@date
			log[date] = Hash.new
			for type in all_type do
				log[date][type] = Array.new
			end
			log_fname = "db/vil/#{@vid}_#{date}.html"
			File.open(log_fname, "r:utf-8") do |ifile|
				ifile.each do |line|
					line.gsub!(/src="img/, %Q(src="../img))
					line.gsub!(/"popup\('img/, %Q["popup('../img])
					line.sub!(/\?cmd=user/, %Q(../index.cgi?cmd=user))
					#line.sub!(/<a href="index\.cgi\?vid=\d+&amp;id=\d+&amp;date=\d+" target="_blank">([^<]+)<\/a>/) { %Q(<span class="char_name">#{$1}</span>) }
					line.sub!(/<a href="\?vid=\d+&id=\d+&date=\d+" target="_blank">([^<]+)<\/a>/) { %Q(<span class="char_name">#{$1}</span>) }
					if (line =~ /^<!--([a-z]+)(\d*)-->/)
						t = $1
						line.gsub!(/^<!--([a-z]+)(\d*)-->/, '')
						if (t == "say")
							#line2 = line.gsub(/href="\?vid=(\d+)&amp;date=(\d+)&amp;log=all#([^"])/) { %Q(href="#{$1}_#{$2}_say.html##{$3}) }
							line2 = line.gsub(/href="\?vid=(\d+)&date=(\d+)&log=all#([^"])/) { %Q(href="#{$1}_#{$2}_say.html##{$3}) }
							log[date]["say"].push(line2)
						elsif (t == "whisper" || t == "whisperhowl")
							#line2 = line.gsub(/href="\?vid=(\d+)&amp;date=(\d+)&amp;log=all#([^"])/) { %Q(href="#{$1}_#{$2}_whisper.html##{$3}) }
							line2 = line.gsub(/href="\?vid=(\d+)&date=(\d+)&log=all#([^"])/) { %Q(href="#{$1}_#{$2}_whisper.html##{$3}) }
							log[date]["whisper"].push(line2)
						elsif (t == "groan")
							#line2 = line.gsub(/href="\?vid=(\d+)&amp;date=(\d+)&amp;log=all#([^"])/) { %Q(href="#{$1}_#{$2}_groan.html##{$3}) }
							line2 = line.gsub(/href="\?vid=(\d+)&date=(\d+)&log=all#([^"])/) { %Q(href="#{$1}_#{$2}_groan.html##{$3}) }
							log[date]["groan"].push(line2)
						elsif (t == "think")
							#line2 = line.gsub(/href="\?vid=(\d+)&amp;date=(\d+)&amp;log=all#([^"])/) { %Q(href="#{$1}_#{$2}_think.html##{$3}) }
							line2 = line.gsub(/href="\?vid=(\d+)&date=(\d+)&log=all#([^"])/) { %Q(href="#{$1}_#{$2}_think.html##{$3}) }
							log[date]["think"].push(line2)
						end
						#line.gsub!(/href="\?vid=([\d]+)&amp;date=([\d]+)&amp;log=all#([^"])/) { %Q(href="#{$1}_#{$2}_all.html##{$3}) }
						line.gsub!(/href="\?vid=([\d]+)&date=([\d]+)&log=all#([^"])/) { %Q(href="#{$1}_#{$2}_all.html##{$3}) }
						log[date]["all"].push(line)
					end
				end
			end
			@log_fnames.push(log_fname)
		end

		for date in 0..@date
			for type in all_type do
				fname = "log/#{@vid}_#{date}_#{type}.html"
				str = ""
				File.open(fname, 'w') do |of|

					of.flock(File::LOCK_EX)
					of.print(HEAD1.gsub(/plugin/, "../plugin"))
					of.print("<title>天国 #{@vid} #{@name}</title>")
					of.print(HEAD2)

					str += %Q(<table width="100%"><tr><td align="center"><table class="main" cellpadding=0 cellspacing=0><tr><td align="left" valign="top"><table class="vil_main"><tr><td width ="#{LIST_WIDTH}"><a href="http://wolften.sakura.ne.jp/">トップページ</a></td><td></td></tr><tr><td></td><td><h2>#{@vid}村 #{@name}</h2><p>)
					date_all = ''
					for i in 0..@date
						datestr =
						if (i == 0)
							"情報"
						else
							"#{i}日目"
						end
						if (i == date)
							date_all += %Q(<span class="today">#{datestr}</span> )
						else
							if (i == 0)
								date_all += %Q(<a href="#{@vid}_#{i}_#{type}.html">#{datestr}</a> )
							else
								date_all += %Q(<a href="#{@vid}_#{i}_#{type}.html">#{datestr}</a> )
							end
						end
					end
					date_all += " |"
					for t in all_type do
						typechar =
						if (t == "say")
							"人"
						elsif(t == "whisper")
							"狼"
						elsif(t == "groan")
							"墓"
						elsif(t == "think")
							"独"
						elsif(t == "all")
							"全"
						end
						if (t == type)
							date_all += %Q( <span class="today">#{typechar}</span>)
						else
							date_all += %Q( <a href="#{@vid}_#{date}_#{t}.html">#{typechar}</a>)
						end
					end
					str += date_all
					str += "</p><td></tr><tr>"
					if (date == 0)
						str += %Q(<td></td><td valign="top">)
						str += erbres('skel/endinfo.html')
					else
						str += %Q(<td valign="bottom"><table class="list"><tr><th colspan="2">生存 #{survivors.size}人</th></tr>)
						str += up_char_list(survivors, date, type)
						str += %Q(<tr><th colspan="2">犠牲 #{@victims.size}人</th></tr>)
						str += up_char_list(@victims, date, type)
						str += %Q(<tr><th colspan="2">処刑 #{@executions.size}人</th></tr>)
						str += up_char_list(@executions, date, type)
						str += %Q(</table></td>)
						str += %Q(<td valign="top">#{log[date][type]})
					end
					str += "</td>"
					str += %Q(</tr><tr><td></td><td><p>#{date_all}</p></td></tr><tr><td><a href="http://wolften.sakura.ne.jp/">トップページ</a></td><td></td></tr></table></td></tr></table></td></tr></table>)
					of.print(str)
					of.print(FOOT)
				end
				if (USE_GZIP)
					system("gzip -c #{fname} > #{fname}.gz.html")
					if (!DEBUG_SHORT)
						unlinks.push(fname)
					end
				end
			end
		end
		unlinks.each do |f|
			File.unlink(f)
		end
	end

	def update
		if (@state == 0)
			up_reset_vote
			up_reset_target
			up_resetremain
			pids.each { |p| p.tenko = -1}
			tenko = -1

			if (!@card)
				up_uptime
				@date += 1
				up_mirror
				change_state
				@wide_comps = nil
				up_resetcnt
				if (@dummy)
					type = 'say'
					@say_cnt[type] = @say_cnt[type] + 1
					cnt = @say_cnt[type]
					player = player_p(1)
					s = say(type, cnt, player, Charset.charsets[@char].dummy_message['next'], MASTER)
					addlog(s)
				end
				return if (up_gameover)
				up_upreset_time
				if (DEBUG)
					@players.each_value do |p|
						STDERR.puts "[DEBUG_ROLE] #{p.name}の役職は#{Skill.skills[p.sid].name}です。"
					end
				end
				return
			end
			up_mirror
			change_state
			@wide_comps = nil
			if (DEBUG)
				@players.each_value do |p|
					STDERR.puts "[DEBUG_ROLE] #{p.name}の役職は#{Skill.skills[p.sid].name}です。"
				end
			end
		end

		if (@state == 3)
			return
		elsif (@state == 2)
			change_state
		elsif(@state == 1)
			if (@night_period)
				if (@night)
					night_update
				else
					day_update
				end
			else
				allday_update
			end
		end
	end
end

