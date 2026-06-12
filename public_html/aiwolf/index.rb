# -*- coding: utf-8 -*-
# require 'jcode'
# $KCODE='e'

require 'cgi'
require 'kconv'
require 'pstore'

require 'util'
require 'login'
require 'player'
require 'vil'
require 'errormsg'
require 'skill'
require 'charset'
require 'conf'

class CWolf
	def initialize
		@cgi = CGI.new(accept_charset: 'EUC-JP')
		@vid = @cgi['vid'].to_i
		if (@vid > 0 && File.exist?("db/vil#{(@vid - 1) / 100}"))
			@vildb = PStore.new("db/vil#{(@vid - 1) / 100}/#{@vid}.db")
		end
	end

	def get_vil_lock(vid)
		v = @vildb.transaction do
			@vildb['root']
		end
		v
	end
	def get_vil(vid)
		v = @vildb['root']
		v
	end

	def handle_move_log
		vldb = PStore.new('db/vil.db')
		state = vldb.transaction do
			return if (!vldb.root?("root#{@vid}"))
			vild = vldb["root#{@vid}"]
			vild['state']
		end
		if (state > 2)
			print "Status: 302 Found\n"
			print "Location: log/#{@vid}_1_all.html\n\n"
			exit(0)
		end
	end

  def handle_remake_villist
    for vid in 2407..10000
      if (vid > 0 && File.exist?("db/vil#{(vid-1)/100}/#{vid}.db"))
        vildb = PStore.new("db/vil#{(vid-1)/100}/#{vid}.db")
      else
        return
      end
      v = vildb.transaction do
        vildb['root']
      end


      vldb = PStore.new('db/vil.db')
      vldb.transaction do
        #vldb.abort if vldb.root?("root#{vid}")
        vldb['recent_vid'] = vid
        vild = Hash.new
        vild['period'] = v.period
        vild['night_period'] = v.night_period
        vild['life_period'] = v.life_period
        vild['state'] = v.state
        vild['name'] = v.name
        vild['sname'] = v.name.jcut
        vild['card'] = v.card
        vild['composition'] = v.composition
        vild['char'] = v.char
        vild['start_hour'] = v.start_hour
        vild['start_min'] = v.start_min
        vild['dummy'] = v.dummy
        vild['open_id'] = v.open_id
        vild['player_num'] = v.players.size
        vild['vid'] = vid

        vldb["root#{vid}"] = vild
      end

    end
  end

	def handle_update
		up_flag = false

		@vil = get_vil_lock(@vid)

		if (!@vil || !File.exist?("db/log#{(@vid - 1) / 100}"))
			print "Status: 302 Found\n"
			print "Location: index.cgi\n\n"
			exit(0)
		end

		if(@vil.death_defeat)
			Skill.skills[1].name = "人喰い"
		end

		if (@vil.state < 3 && @vil.update_time && @vil.update_time < Time.now.to_i)
			@vildb.transaction do
				@vil = get_vil(@vid)
				if (@vil.update_time < Time.now.to_i)
					@vil.update
					up_flag = true
				end
			end
		elsif (@vil.state == 0 && @vil.upstart_time && @vil.upstart_time < Time.now.to_i)
			@vildb.transaction do
				@vil = get_vil(@vid)
				if (@vil.upstart_time < Time.now.to_i && @vil.state == 0 && @vil.players.size <= @vil.entry_max)
					if (@vil.players.size < @vil.entry_min || (@vil.composition == WIDE_CUSTOM && !@vil.wide_comps[@vil.players.size]))
						@vil.upstart_time += 24*60*60
					else
						@vil.update_time = @vil.upstart_time
						@vil.update
						up_flag = true
					end
				end
			end
		elsif (@vil.state == 1 && @vil.upreset_time && @vil.upreset_time < Time.now.to_i)
			@vildb.transaction do
				@vil = get_vil(@vid)
				if (@vil.upreset_time < Time.now.to_i)
					@vil.up_upreset_time
				end
		  end
		elsif (@vil.state == 0) && ((@vil.vildead_time && @vil.vildead_time < Time.now) || (!@vil.vildead_time))
      @vildb.transaction do
        @vil = get_vil(@vid)
        @vil.vil_dead
        up_flag = true
      end
	  end
		return up_flag
	end

	def handle_vid
		handle_update
		#handle_move_log

		print_head("#{@vil.vid} #{@vil.name}")
		erbrun('skel/vil.html')
		print(FOOT)
	end

	def handle_entry
		pid = @cgi['pid'].to_i
		pass = @cgi['pass']
		msg = @cgi['message']
		skill = @cgi['skill'].to_i

		return if (!@login.login)
		return if (!msg || msg == '')

		j_data = @cgi['j_data']
		j_code = NKF.guess(j_data)
		opt =
			if (j_code == NKF::JIS)
				'-xwJ'
			elsif (j_code == NKF::EUC)
				'-xwE'
			elsif (j_code == NKF::SJIS)
				'-xwS'
			elsif (j_code == NKF::UTF8)
				'-xwW'
			elsif (j_code == NKF::UTF16)
				'-xwW16'
			else
				'-xw'
			end
		msg = NKF.nkf(opt, msg)
		msg = CGI.escapeHTML(msg)
		msg.gsub!(/\r\n/, '<br>')
		msg.gsub!(/[\r\n]/, '<br>')
		msg.gsub!(/&amp;(#\d{3,};)/) { '&' + $1 }
		msg.gsub!(/&(#0*127;)/) { '&amp;' + $1 }
		msg.gsub!(/^ +$/, '　')

		num_char = 1

		@vildb.transaction do
			vil = get_vil(@vid)

			return if (vil.players.key?(@login.userid))
			return if (vil.state != 0)
			return if (vil.players.size >= vil.entry_max)
			return if (vil.pass.to_s != pass.to_s)

			ps = vil.players.values.select {|p| p.pid == pid}

			if (!vil.num_char[pid])
				vil.num_char[pid] = 1
			end

			for i in 1..(ps.size + 1)
				if (ps.all? {|p| p.num_char != i})
					num_char = i

					for j in (num_char + 1)..(ps.size + 2)
						if (ps.all? {|p| p.num_char != j})
							vil.num_char[pid] = j
							break
						end
					end
					break
				end
			end

			if (@login.userid != MASTER)
				player = Player.new(pid, @login.userid, vil.num_id, skill, Charset.charsets[vil.char].char_names[pid], num_char)
				vil.num_id += 1
			else
				vil.dummy = true
				player = Player.new(pid, @login.userid, 1, skill, Charset.charsets[vil.char].char_names[pid], num_char)
			end

			vil.add_player(player)

			type = 'say'
			vil.addlog(announce("#{player.name} が集会所を訪れました。"))
			vil.say_cnt[type] = vil.say_cnt[type] + 1
			cnt = vil.say_cnt[type]
			vil.addlog(vil.say(type, cnt, player, msg, player.userid))
		end
	end

	def print_head(title = nil)
		@headered = true
		print "Content-Type: text/html; charset=UTF-8\n\n"
    	print(HEAD1)
		if (title)
			print "<title>AI天国 #{title}</title>"
		else
			print "<title>AI天国</title>"
		end

		if (@cgi['date'] == "0" || @cgi['cmd'] == 'mkvil')
			print(HEAD2ED)
		elsif (@vid >= 1)
			print(HEAD2VIL)
		else
			print(HEAD2)
		end
	end

	def handle_index
		show = Array.new
		vldb = PStore.new('db/vil.db')
		vldb.transaction do
			if (vldb.root?('recent_vid'))
				fid = 0
				while (!File.exist?("db/vil#{fid}"))
					fid = fid + 1
				end
				for i in (fid * 100 + 1)..vldb['recent_vid']
					return if (!vldb.root?("root#{i}"))

					vild = vldb["root#{i}"]
					if (vild['state'] == 2 && File.exist?("db/vil#{(i - 1) / 100}/#{i}.db"))
						show.push(i)
					end
				end
			end
		end
		show.each do |i|
			@vid = i
			@vildb = PStore.new("db/vil#{(@vid - 1) / 100}/#{@vid}.db")
			handle_update
		end
		erbrun('skel/villist.html')
	end

	def handle_vote
		v = @cgi['vote_id'].to_i
		d = @cgi['set_date'].to_i
		return if (!@login.login)

		@vildb.transaction do
			vil = get_vil(@vid)
			return if(vil.state != 1)
			return if(vil.night)
			return if (d != vil.date)
			player = vil.player(@login)
			return if (!player)
			# 自分自身への投票を禁止する
			return if (v != -1 && v == player.num_id)
			player.vote = v
			if (v == -1)
				str = "#{player.name} が投票を取り消しました。"
			else
				str = "#{player.name} が #{vil.player_p(v).name} に投票しました。"
			end
			vil.addlog(setvote(player.num_id, str))
			if (!vil.pids.find { |p| p.vote == -1 })
        		if (vil.update_time && vil.update_time > Time.now.to_i)
					vil.update_time = Time.now.to_i
					vil.update
				end
			end
		end
	end

	def handle_skill
		t = @cgi['target_id'].to_i
		d = @cgi['set_date'].to_i
		return if (!@login.login)

		@vildb.transaction do
			vil = get_vil(@vid)
			return if(vil.state != 1)
			return if (d != vil.date)
			player = vil.player(@login)
			return if(!player)
			return if(player.dead != 0)
			target_p = vil.player_p(t)
			return if(t != -1 && (!target_p || target_p.dead != 0) && player.sid != 4)
			# sid=4(狂人)以外は自分自身をターゲットにできない
			return if (t != -1 && t == player.num_id && player.sid != 4)
			# 人狼の初日襲撃においてダミー以外は狙えないようにする
			return if (player.sid == 1 && vil.attack_dummy(vil.date) && t != -1 && t != 1)
			if (player.sid == 12)
				t2 = @cgi['target_id2'].to_i
				if (t == t2 || t == -1 || t2 == -1)
					str = "#{player.name} は矢を撃つ対象選択を取り消します。"
					player.target = -1
					player.target2 = -1
				elsif
					str = "#{player.name} は #{vil.player_p(t).name} と #{vil.player_p(t2).name} に愛の矢を撃ちます。"
					player.target = t
					player.target2 = t2
				end
				vil.addlog(cupid_announce(str, player.num_id))
      elsif (player.sid == 4)
				player.target = t
				if (t == -1)
					str = settarget(player)
				else
					str = settarget(player, true)
				end
				vil.addlog(str)
			else
				player.target = t
				if (t == -1)
					str = settarget(player)
				else
					str = settarget(player, vil.player_p(t).name)
				end
				vil.addlog(str)
			end
			if (vil.night_commit && !vil.skill_pids.find { |p| p.target == -1 })
        		if (vil.update_time && vil.update_time > Time.now.to_i && vil.night)
					vil.update_time = Time.now.to_i
					vil.update
				end
			end
		end
	end

	def handle_upstart
		@vil = get_vil_lock(@vid)
		if (@vil.state == 0 && @vil.players.size >= @vil.entry_min && @vil.players.size <= @vil.entry_max)
			if(@vil.composition != WIDE_CUSTOM || @vil.wide_comps[@vil.players.size])
				# 進行中の村が既にある場合は開始を拒否する（MASTER/ADMINは除外）
				if (@login.userid != MASTER && @login.userid != ADMIN)
					vldb_check = PStore.new('db/vil.db')
					in_progress = vldb_check.transaction(true) do
						recent_vid = vldb_check['recent_vid'].to_i
						min = (recent_vid - 100 > 1) ? recent_vid - 100 : 1
						(min..recent_vid).any? do |i|
							vild = vldb_check["root#{i}"]
							vild && vild['state'] == 1
						end
					end
					if (in_progress)
						raise ErrorMsg.new("現在進行中の村があります。進行中の村が終了してから開始してください。")
					end
				end

				@vildb.transaction do
					@vil = get_vil(@vid)
					return if (@vil.userid != @login.userid && @login.userid != MASTER && @login.userid != ADMIN)
					if (@vil.state == 0 && @vil.players.size >= @vil.entry_min && @vil.players.size <= @vil.entry_max)
						if(@vil.composition != WIDE_CUSTOM || @vil.wide_comps[@vil.players.size])
							# トランザクション内でも再チェック（競合防止）
							if (@login.userid != MASTER && @login.userid != ADMIN)
								vldb2 = PStore.new('db/vil.db')
								in_progress2 = vldb2.transaction(true) do
									recent_vid = vldb2['recent_vid'].to_i
									min = (recent_vid - 100 > 1) ? recent_vid - 100 : 1
									(min..recent_vid).any? do |i|
										next if i == @vid
										vild = vldb2["root#{i}"]
										vild && vild['state'] == 1
									end
								end
								return if (in_progress2)
							end

							@vil.update
							vldb = PStore.new('db/vil.db')
							vldb.transaction do
								vild =vldb["root#{@vid}"]
								vild['upstart_time'] = nil
							end
						end
					end
				end
			end
		end
	end

	def handle_super_commit
		@vildb.transaction do
			vil = get_vil(@vid)
			return if (vil.userid != @login.userid && @login.userid != MASTER)
			if (vil.update_time && vil.update_time > Time.now.to_i)
				vil.update_time = Time.now.to_i
				vil.update
			end
		end
	end

	def handle_conf
		Conf.new(@login.userid, @cgi)
	end

	def handle_exit
		id = @cgi['exit_id'].to_i
    	@vildb.transaction do
			vil = get_vil(@vid)
			p = vil.player_p(id)

			return if (!p)
			return if (vil.state != 0)

			if (p.userid == MASTER)
				vil.dummy = false
			end

			if (p.num_char < vil.num_char[p.pid])
				vil.num_char[p.pid] = p.num_char
			end
			s = announce("#{p.name} が村を去りました。")
			vil.addlog(s)
			vil.players.delete(p.userid)

			vldb = PStore.new('db/vil.db')
			vldb.transaction do
				vild = vldb["root#{@vid}"]
				vild['player_num'] = vil.players.size
				vild['dummy'] = vil.dummy
			end
		end
	end

	def handle_commit
		v = @cgi['commit_value'].to_i
		return if (!@login.login)
		@vildb.transaction do
			vil = get_vil(@vid)
			return if(vil.night)
			return if (vil.date != 2 || vil.card || vil.state != 1)
			player = vil.player(@login)
			return if (!player)
			player.commit = v
			if (v == -1)
				str = "#{player.name} が時間を進めるを取り消しました。"
			else
				str = "#{player.name} が時間を進めるを選択しました。"
			end
			vil.addlog(setvote(player.num_id, str))

			if (!vil.pids.find { |p| p.commit == -1 && p.userid != MASTER})
				if (vil.update_time && vil.update_time > Time.now.to_i)
					vil.pids.each { |p| p.commit = 0}
					vil.update
				end
			end
		end
	end

	def handle_dummy_in
		@vildb.transaction do
			vil = get_vil(@vid)
			return if (vil.state != 0)
			return if (vil.pids.find { |p| p.userid == MASTER})
			return if (vil.composition == CUSTOM && vil.skill_nums[0] == 0)
			return if (vil.players.size >= vil.entry_max)
			return if (vil.composition == WIDE_CUSTOM && vil.wide_comps.any? { |w| w && /村/ !~ w})

			vil.dummy = true

			player = Player.new(0, MASTER, 1, 0, Charset.charsets[vil.char].char_names[0], 1)
			vil.add_player(player)

			type = 'say'
			vil.say_cnt[type] = vil.say_cnt[type] + 1
			cnt = vil.say_cnt[type]
			player = vil.player_p(1)
			vil.addlog(announce("#{player.name} が集会所を訪れました。"))
			vil.addlog(vil.say(type, cnt, player, Charset.charsets[vil.char].dummy_message['middle'], player.userid))
			vldb = PStore.new('db/vil.db')
			vldb.transaction do
				vild = vldb["root#{@vid}"]
				vild['player_num'] = vil.players.size
				vild['dummy'] = vil.dummy
			end
		end
	end

	def handle_profile
		return if (!@login.login)
		pro_text = @cgi['pro_text']
		prodb = PStore.new('db/profile.db')
		prodb.transaction do
			return if (!prodb.root?(@login.userid))
			pro_text = CGI.escapeHTML(pro_text)
			pro_text.gsub!(/\r\n/, '<br>')
			pro_text.gsub!(/[\r\n]/, '<br>')
			prodb[@login.userid]['pre'] = pro_text.gsub(/<br>/, "&#13;")
			pro_text.gsub!(%r|\[([^\]]+?):((([^:/?#\]]+):)(//([^/?#\]]*))?([^?#\]]*)(\?([^#\]]*))?(#(.[^\]]))?)\]|) { %Q(<a href="#{$2}">#{$1}</a>) }
			prodb[@login.userid]['text'] = pro_text
		end
	end

	def handle_pscomp
		return if (!@login.login)
		comp_text = @cgi['comp_text']
		comp_text.gsub!(/Q/, 'Ｑ')
		comp_text.gsub!(/C/, 'Ｃ')
		comp_text.gsub!(/ダ/, '村')
		vals = comp_text.split(/\r\n|[\r\n]/)
		po = Composition.compositions[POSTING]
		pscompdb = PStore.new('db/pscomp.db')
		pscompdb.transaction do
			for i in 0...vals.size do
				a = Array.new
				sum = 0
				for j in 0...Skill.skills.size do
					n = vals[i].count(Skill.skills[j].sname)
					a.push(n)
					sum += n
				end
				next if (sum > po.max || sum < po.min)
				if (!pscompdb.root?(sum))
					pscompdb[sum] = Array.new
				end
				s = ''
				for k in 0...Skill.skills.size do
					for l in 0...a[k] do
						s += Skill.skills[k].sname
					end
				end
				if (pscompdb[sum].all? { |c| c['comp'] != s })
					h = Hash.new
					h['comp'] = s
					h['userid'] = @login.userid
					pscompdb[sum].push(h)
				end
			end
		end
	end

	def handle_delcomp
		return if (!@login.login)
		po = Composition.compositions[POSTING]
		pscompdb = PStore.new('db/pscomp.db')
		pscompdb.transaction do
			for n in  po.min..po.max do
				next if (!pscompdb.root?(n))
				psn = pscompdb[n]
				for i in 0...psn.size do
					next if (@cgi["#{n}_#{i}"] != "on")
					next if (@login.userid != MASTER && @login.userid != psn[i]['userid'])
					psn.delete_at(i)
				end
			end
		end
	end

	def handle_tenko
		t = @cgi['tenko_value'].to_i
		return if (!@login.login)
		@vildb.transaction do
			vil = get_vil(@vid)
			return if (vil.state != 0)
			player = vil.player(@login)
			return if (vil.userid != @login.userid && @login.userid != MASTER && @login.userid != ADMIN)
			if (t == 0)
				str = "点呼が開始されました。"
				vil.addlog(announce(str))
			elsif(vil.tenko != -1)
				str = "点呼が中止されました。"
				vil.addlog(announce(str))
			end
			vil.tenko = t

			vil.pids.each { |p| p.tenko = -1}
		end
	end

	def handle_cmd
		cmd = @cgi['cmd']
		cmd = 'msg' if (cmd == 'prv')
		if (@vid != 0 && handle_update)
			if (cmd == 'msg')
				handle_message
			end
		else
			if (cmd == 'mkvil')
      				handle_mkvil
			elsif (cmd == 'edvil')
				handle_edvil
			elsif (cmd == 'entry')
				handle_entry
			elsif (cmd == 'msg')
				handle_message
			elsif (cmd == 'upstart')
				handle_upstart
			elsif (cmd == 'vote')
				handle_vote
			elsif (cmd == 'skill')
				handle_skill
			elsif (cmd == 'exit')
				handle_exit
			elsif (cmd == 'commit')
				handle_commit
			elsif (cmd == 'super_commit')
				handle_super_commit
			elsif (cmd == 'conf')
				handle_conf
			elsif (cmd == 'dummy_in')
				handle_dummy_in
			elsif (cmd == 'profile')
				handle_profile
			elsif (cmd == 'pscomp')
				handle_pscomp
			elsif (cmd == 'delcomp')
				handle_delcomp
			elsif (cmd == 'tenko')
				handle_tenko
			end
		end
	end

	def handle_prv
		msg = @cgi['message']
		type = 'say'
		return false if (@cgi['think'] == 'on' || @cgi['groan'] == 'on')
		return false if (!msg || msg == '')
		j_data = @cgi['j_data']
		j_code = NKF.guess(j_data)
		opt =
			if (j_code == NKF::JIS)
				'-xwJ'
			elsif (j_code == NKF::EUC)
				'-xwE'
			elsif (j_code == NKF::SJIS)
				'-xwS'
			elsif (j_code == NKF::UTF8)
				'-xwW'
			elsif (j_code == NKF::UTF16)
				'-xwW16'
			else
				'-xw'
			end
		msg = NKF.nkf(opt, msg)
		len = PRV_LEN
		@val_msg = msg[0..len]
	    if (/.\z/ !~ @val_msg)
	        @val_msg[-1,1] = ''
			cut = msg[len..-1]
		else
			cut = msg[(len + 1)..-1]
	    end
		str = CGI.escapeHTML(@val_msg)
		@val_msg = CGI.escape(@val_msg)
		str.gsub!(/\r\n/, '<br>')
		str.gsub!(/[\r\n]/, '<br>')
		str.gsub!(/&amp;(#\d{3,};)/) { '&' + $1 }
		str.gsub!(/&(#0*127;)/) { '&amp;' + $1 }
		str.gsub!(/^ +$/, '　')
		if (@cgi['loud'] == 'on')
			str = "<div class=\"loud\">#{str}</div>"
		end
		if (cut)
			cut = CGI.escapeHTML(cut)
			cut.gsub!(/\r\n/, '<br>')
			cut.gsub!(/[\r\n]/, '<br>')
			str += %Q(<span class="cut">#{cut}</span>)
		end

		vil = get_vil_lock(@vid)
		return false if (!vil)
		return false if (vil.state != 1)
		return false if (!(vil.period >= LONG && vil.state == 1))
		return false if (!@login.login)
		@player = vil.player(@login)
		return false if (!@player)
		@prv_str = vil.prv(type, vil.say_cnt[type] + 1, @player, str)
		return true
	end

	def handle_message
		msg = @cgi['message']
		msg = CGI.unescape(msg) if (@cgi['prv'] == 'on')
		guest = (@cgi['guest'] == 'on')

		type =
			if (@cgi['think'] == 'on')
				'think'
			elsif (@cgi['whisper'] == 'on')
				'whisper'
			elsif (@cgi['groan'] == 'on')
				'groan'
			elsif (@cgi['action'] == 'on')
				'action'
			else
				'say'
			end

		c_msg = msg.gsub(/\r\n/, '')
		c_msg = msg.gsub(/[\r\n]/, '')
		return if (!c_msg || c_msg == '')
		j_data = @cgi['j_data']
		j_code = NKF.guess(j_data)
		opt =
			if (j_code == NKF::JIS)
				'-xwJ'
			elsif (j_code == NKF::EUC)
				'-xwE'
			elsif (j_code == NKF::SJIS)
				'-xwS'
			elsif (j_code == NKF::UTF8)
				'-xwW'
			elsif (j_code == NKF::UTF16)
				'-xwW16'
			else
				'-xw'
			end
		msg = NKF.nkf(opt, msg)
		msg = msg.acut if (type == 'action')
		msg = CGI.escapeHTML(msg)
		msg.gsub!(/\r\n/, '<br>')
		msg.gsub!(/[\r\n]/, '<br>')
		msg.gsub!(/&amp;(#\d{3,};)/) { '&' + $1 }
		msg.gsub!(/&(#0*127;)/) { '&amp;' + $1 }
		msg.gsub!(/^ +$/, '　')
		msg = "　" if (msg == "")

		@vildb.transaction do
			vil = get_vil(@vid)
			return if (vil.state > 2)
			if (@login.login)
				if (@cgi['loud'] == 'on')
					msg = "<div class=\"loud\">#{msg}</div>"
				elsif (@cgi['small_voice'] == 'on')
					msg = "<div class=\"small_voice\">#{msg}</div>"
				end
				if (!guest)
					player = vil.player(@login)
					return if (!player)

					if (player.dead != 0 && type == 'say')
						type = 'groan'
					end
					if (player.dead == 0 && type == 'groan')
						type = 'think'
					end
					if (vil.night && type == 'say' && vil.state == 1)
						type = 'think'
					end
					if (player.dead != 0 && type == 'whisper')
	          			type = 'think'
	        		end
					if (vil.state != 1 && type == 'whisper')
	          			type = 'think'
	        		end
					if (vil.card && !vil.night && type == 'whisper')
	          			type = 'think'
	        		end
					if (vil.period >= LONG && vil.state == 1 && type == 'say')
						return if (player.say_remain == 0)
						player.say_remain -= 1
					end
					if (type == 'action')
						return if (vil.date != @cgi['set_date'].to_i)
						return if (player.dead != 0 || vil.night)
						postpos = POSTPOS[@cgi['postpos'].to_i]
						postpos = "" if (postpos == "　")
						if (@cgi['action_id'] != "")
							p = vil.player_p(@cgi['action_id'].to_i)
							return if(!p)
							msg = postpos + p.name + msg
						else
							msg = postpos + msg
						end
						if(vil.period >= LONG && vil.state == 1)
							return if (player.action_remain == 0)
							player.action_remain -= 1
						end
						s = vil.say_action(player, msg)
						vil.addlog(s)
					else
						vil.say_cnt[type] = vil.say_cnt[type] + 1
						cnt = vil.say_cnt[type]
						s = vil.say(type, cnt, player, msg, @login.userid)
						vil.addlog(s)
					end

				else
					if (vil.state == 1)
						type = 'groan'
					end
					vil.say_cnt[type] = vil.say_cnt[type] + 1
					cnt = vil.say_cnt[type]
					s = vil.say(type, cnt, nil, msg, @login.userid)
					vil.addlog(s)
				end
			end
        	end
	end

	def handle_mkvil
		return if (!@login.login)
		name = @cgi['name']
		sname = name.jcut
    pass = @cgi['pass']
		period = @cgi['time'].to_i
		night_period = @cgi['night_time'].to_i
		life_period = @cgi['life_time'].to_i

		start_hour = (@cgi['start_hour'] =~ /^\d+$/) ? @cgi['start_hour'].to_i : nil
		start_min = @cgi['start_min'].to_i

		entry_max = @cgi['entry_max'].to_i
		entry_min = @cgi['entry_min'].to_i

		dummy_num = @cgi['dummy_num'].to_i
		composition = @cgi['composition'].to_i
		char = @cgi['char'].to_i

		dummy = (@cgi['dummy'] == 'on')
		first_guard = (@cgi['first_guard'] == 'on')
		card = (@cgi['card'] == 'on')
		open_vote = (@cgi['open_vote'] == 'on')
		hope_skill = (@cgi['hope_skill'] == 'on')
		night_commit = (@cgi['night_commit'] == 'on')
		open_id = (@cgi['open_id'] == 'on')
		open_skill = (@cgi['open_skill'] == 'on')
		possessed = (@cgi['possessed'] == 'on')
		death_defeat = (@cgi['death_defeat'] == 'on')
    remainflag = (@cgi['remainflag'] == 'on')

    sayfull = @cgi['sayfull'].to_i
    actfull = @cgi['actfull'].to_i

		return if (!name || name == '')
		name = CGI.escapeHTML(name)
		name.gsub!(/^[ 　]+$/, '村')
		sname = CGI.escapeHTML(sname)
		sname.gsub!(/^[ 　]+$/, '村')

		skill_nums = Array.new

		all_skill_num = 0
		if (composition == CUSTOM)
		    for i in 0...Skill.skills.size
				n = @cgi["skill_num#{i}"].to_i
				n = 99 if (n > 99)
				n = 0 if (n < 0)
				all_skill_num += n
				skill_nums.push(n)
		    end
			return if (all_skill_num < 1)
			return if (dummy && skill_nums[0] < 1)
		elsif (composition == WIDE_CUSTOM)
			comp_text = @cgi['wide_comp']
			comp_text.gsub!(/Q/, 'Ｑ')
			comp_text.gsub!(/C/, 'Ｃ')
			comp_text.gsub!(/ダ/, '村')
			vals = comp_text.split(/\r\n|[\r\n]/)
			po = Composition.compositions[WIDE_CUSTOM]
			wide_comps = Array.new
			for i in 0...vals.size do
				a = Array.new
				sum = 0
				for j in 0...Skill.skills.size do
					n = vals[i].count(Skill.skills[j].sname)
					a.push(n)
					sum += n
				end
				next if(sum > po.max || sum < po.min)
				next if(wide_comps[sum])
				next if (dummy && a[0] < 1)
				s = ''
				for k in 0...Skill.skills.size do
					for l in 0...a[k] do
						s += Skill.skills[k].sname
					end
				end
				wide_comps[sum] = s
			end
			return if (wide_comps.empty?)
		end

		period = (period > 0) ? period : 1
		if (card)
			night_period = (night_period > 0) ? night_period : 1
		else
			night_period = (night_period > 0) ? night_period : nil
		end
		life_period = 0 if (!night_period)
		life_period = (life_period > 0) ? life_period : nil

		if (DEBUG)
			if (dummy_num > 16)
				dummy_num = 16
			end
		end

		if (DEBUG)
			skill = 0
			num_char = 1
			du = ['1', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 'o']
		end

		vldb = PStore.new('db/vil.db')
		vid = vldb.transaction do
			recent_vid = vldb['recent_vid'].to_i
			min = (recent_vid - 50 > 1 ) ? recent_vid - 50 : 1
			unused = 0
			(recent_vid).downto(min) do |i|
				vild = vldb["root#{i}"]
				next if (!vild)
				if (vild['state'] == 0)
					unused = unused + 1
				end
			end
			return if (unused >= 20)

			vid = vldb['recent_vid'].to_i + 1
			vldb['recent_vid'] = vid

			vild = Hash.new
			vild['period'] = period
			vild['night_period'] = night_period
			vild['life_period'] = life_period
			vild['state'] = 0
			vild['name'] = name
			vild['sname'] = sname
			vild['card'] = card
			vild['composition'] = composition
			vild['char'] = char
			vild['start_hour'] = start_hour
			vild['start_min'] = start_min
			vild['dummy'] = dummy
			vild['open_id'] = open_id
			vild['player_num'] = 0
			vild['vid'] = vid

			vldb["root#{vid}"] = vild

			if (!File.exist?("db/vil#{(vid - 1) / 100}"))
				Dir::mkdir("db/vil#{(vid - 1) / 100}", 0700)
			end
			if (!File.exist?("db/log#{(vid - 1) / 100}"))
				Dir::mkdir("db/log#{(vid - 1) / 100}", 0700)
			end

			vid
		end

		@vildb = PStore.new("db/vil#{(vid - 1) / 100}/#{vid}.db")
		vil = @vildb.transaction do
			vil = Vil.new(name, pass, vid, @login.userid, period, night_period, life_period, composition, skill_nums, all_skill_num, wide_comps, char,
							start_hour, start_min, entry_max, entry_min, dummy, first_guard, card, open_vote, hope_skill, night_commit, open_id, open_skill, death_defeat, possessed, sayfull, actfull, remainflag)
			@vildb['root'] = vil

			vldb.transaction do
				vild =vldb["root#{vid}"]
				vild['upstart_time'] = vil.upstart_time
				vild['start_hour'] = vil.start_hour
				vild['start_min'] = vil.start_min
				vild['entry_max'] = vil.entry_max
			end

			if (dummy)
				player = Player.new(0, MASTER, 1, 0, Charset.charsets[vil.char].char_names[0], 1)
				vil.add_player(player)
			end

			if (DEBUG)
				for pid in 1...(dummy_num + 1)
					ps = vil.players.values.select {|p| p.pid == pid}
					if (ps.size > 0)
						for i in 1..(ps.size + 1)
							if (ps.all? {|p| p.num_char != i})
								num_char = i

								for j in (num_char + 1)..(ps.size + 2)
									if (ps.all? {|p| p.num_char != j})
										vil.num_char[pid] = j
										break
									end
								end
								break
							end
						end
					elsif
						vil.num_char[pid] += 1
					end
					player = Player.new(pid, du[pid], vil.num_id, skill, Charset.charsets[vil.char].char_names[pid], num_char)
					vil.add_player(player)
					vil.num_id += 1
				end
			end

			vil
		end
		vid = vil.vid

		File.open("db/log#{(vid - 1) / 100}/#{vid}_1.html", 'a') do |of|
			of.flock(File::LOCK_EX)
			of.print(announce(OPENING))
		end

		@vildb.transaction do
			vil = get_vil(vid)
			type = 'say'

			if (dummy)
				vil.say_cnt[type] = vil.say_cnt[type] + 1
				cnt = vil.say_cnt[type]
				player = vil.player_p(1)
				vil.addlog(announce("#{player.name} が集会所を訪れました。"))
				vil.addlog(vil.say(type, cnt, player, Charset.charsets[vil.char].dummy_message['entry'], player.userid))
			end

			if (DEBUG)
				for i in 2...(dummy_num + 2)
					vil.say_cnt[type] = vil.say_cnt[type] + 1
					cnt = vil.say_cnt[type]
					player = vil.player_p(i)
					vil.addlog(announce("#{player.name} が集会所を訪れました。"))
					vil.addlog(vil.say(type, cnt, player, 'ふぁーあ、眠いよ…パトラッシュ…。', player.userid))
				end
			end
		end
	end

	def handle_edvil
		return if (!@login.login)
		name = @cgi['name']
		sname = name.jcut
		period = @cgi['time'].to_i
		night_period = @cgi['night_time'].to_i
		life_period = @cgi['life_time'].to_i

		start_hour = (@cgi['start_hour'] =~ /^\d+$/) ? @cgi['start_hour'].to_i : nil
		start_min = @cgi['start_min'].to_i

		entry_max = @cgi['entry_max'].to_i
		entry_min = @cgi['entry_min'].to_i

		composition = @cgi['composition'].to_i

		first_guard = (@cgi['first_guard'] == 'on')
		card = (@cgi['card'] == 'on')
		open_vote = (@cgi['open_vote'] == 'on')
		hope_skill = (@cgi['hope_skill'] == 'on')
		night_commit = (@cgi['night_commit'] == 'on')
		open_id = (@cgi['open_id'] == 'on')
		open_skill = (@cgi['open_skill'] == 'on')
		death_defeat = (@cgi['death_defeat'] == 'on')
		possessed = (@cgi['possessed'] == 'on')
    remainflag = (@cgi['remainflag'] == 'on')

    sayfull = @cgi['sayfull'].to_i
    actfull = @cgi['actfull'].to_i

		return if (!name || name == '')
		name = CGI.escapeHTML(name)
		name.gsub!(/^ +$/, '村')
		sname = CGI.escapeHTML(sname)
		sname.gsub!(/^ +$/, '村')

		period = (period > 0) ? period : 1
		if (card)
			night_period = (night_period > 0) ? night_period : 1
		else
			night_period = (night_period > 0) ? night_period : nil
		end
		life_period = 0 if (!night_period)
		life_period = (life_period > 0) ? life_period : nil

		@vildb.transaction do
			vil = get_vil(@vid)
			return if (vil.state != 0)
			return if (vil.userid != @login.userid && @login.userid != MASTER && @login.userid != ADMIN)

			skill_nums = Array.new
			all_skill_num = 0
			if (composition == CUSTOM)
			    for i in 0...Skill.skills.size
					n = @cgi["skill_num#{i}"].to_i
					n = 99 if (n > 99)
					n = 0 if (n < 0)
					all_skill_num += n
					skill_nums.push(n)
			    end
				return if (all_skill_num < 1)
				return if (vil.players.size > all_skill_num)
				return if (vil.dummy && skill_nums[0] < 1)
			elsif (composition == WIDE_CUSTOM)
				comp_text = @cgi['wide_comp']
				comp_text.gsub!(/Q/, 'Ｑ')
				comp_text.gsub!(/C/, 'Ｃ')
				comp_text.gsub!(/ダ/, '村')
				vals = comp_text.split(/\r\n|[\r\n]/)
				po = Composition.compositions[WIDE_CUSTOM]
				wide_comps = Array.new
				for i in 0...vals.size do
					a = Array.new
					sum = 0
					for j in 0...Skill.skills.size do
						n = vals[i].count(Skill.skills[j].sname)
						a.push(n)
						sum += n
					end
					next if(sum > po.max || sum < po.min)
					next if(wide_comps[sum])
					next if (vil.dummy && a[0] < 1)
					s = ''
					for k in 0...Skill.skills.size do
						for l in 0...a[k] do
							s += Skill.skills[k].sname
						end
					end
					wide_comps[sum] = s
				end
				return if (wide_comps.empty?)
			end

			if (composition != CUSTOM)
				return if (vil.players.size > Composition.compositions[composition].max)
			end

			vil.edit(name, period, night_period, life_period, composition, skill_nums, all_skill_num, wide_comps,
						start_hour, start_min, entry_max, entry_min, first_guard, card, open_vote, hope_skill, night_commit, open_id, open_skill, death_defeat, possessed, sayfull, actfull, remainflag)

			vldb = PStore.new('db/vil.db')
			vldb.transaction do
				vild = vldb["root#{@vid}"]
				vild['name'] = @cgi['name']
				vild['sname'] = sname
				vild['period'] = period
				vild['night_period'] = night_period
				vild['life_period'] = life_period
				vild['card'] = card
				vild['composition'] = composition
				vild['upstart_time'] = vil.upstart_time
				vild['start_hour'] = vil.start_hour
				vild['start_min'] = vil.start_min
				vild['entry_max'] = vil.entry_max
				vild['open_id'] = open_id
			end
		end
	end
	def run
		@headered = false
		head = "Content-Type: text/html; charset=UTF-8\n\n"

		begin
		@login = Login.new(@cgi)

		if (@login.cookie)
			print "Set-Cookie: #{@login.cookie}\n"
		end

		if (ENV['REQUEST_METHOD'] == 'POST')
			if (@cgi['cmd'] == 'prv' && handle_prv)
				print_head
				erbrun('skel/prv.html')
				print(FOOT)
				return
			end
			handle_cmd

			print "Status: 302 Found\n"
			if (@vid != 0)
				if (@cgi['cmd'] != 'edvil')
					print "Location: ?vid=#{@vid}#form\n\n"
				else
					print "Location: ?vid=#{@vid}&date=0\n\n"
				end
			elsif (@cgi['cmd'] == 'conf')
				print "Location: ?cmd=conf\n\n"
			elsif (@cgi['cmd'] == 'profile')
				print "Location: ?cmd=user&uid=#{CGI.escape(@login.userid)}\n\n"
			elsif (@cgi['cmd'] == 'pscomp')
				print "Location: ?cmd=pscomp\n\n"
			elsif (@cgi['cmd'] == 'delcomp')
				print "Location: ?cmd=pscomp\n\n"
			else
				print "Location: index.cgi\n\n"
			 end
        	return
		end

		if (@cgi['cmd'] == 'mkvil')
			print_head
	        	erbrun('skel/mkvil.html')
	        	print(FOOT)
			return
		elsif (@cgi['cmd'] == 'userlist')
			print_head
	        	erbrun('skel/userlist.html')
	        	print(FOOT)
			return
		elsif (@cgi['cmd'] == 'user')
			print_head
	        	erbrun('skel/user.html')
	        	print(FOOT)
			return
		elsif (@cgi['cmd'] == 'char')
			print_head
	        	erbrun('skel/char.html')
	        	print(FOOT)
			return
		elsif (@cgi['cmd'] == 'conf')
			print_head
	        	erbrun('skel/conf.html')
	        	print(FOOT)
			return
		elsif (@cgi['cmd'] == 'doc')
			print_head
	        	erbrun('skel/doc.html')
	        	print(FOOT)
			return
		elsif (@cgi['cmd'] == 'pscomp')
			print_head
	        	erbrun('skel/pscomp.html')
	        	print(FOOT)
			return
		end

		if (@vildb && @vid != 0)
			handle_vid
		else
			print_head
      #handle_remake_villist
			handle_index
			print(FOOT)
		end

		rescue ErrorMsg
			if (!@headered)
				print head + "\r\n"
			end
			print $!
		rescue
			if (!@headered)
				print head + "\r\n"
			end
			print "<pre>\n"
			print "#{$!.to_s}\n"
			print "#{$!.backtrace.join("\n")}\n"
			print "</pre>\n"
		end
	end
end

CWolf.new.run

