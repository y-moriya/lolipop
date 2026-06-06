# -*- coding: utf-8 -*-
require 'cgi'
require 'json'
require 'pstore'
require 'time'
require 'util'
require 'login'
require 'player'
require 'vil'
require 'skill'
require 'charset'
require 'conf'

class Api
  def initialize
    @cgi = CGI.new(accept_charset: "UTF-8")
    @cmd = @cgi['cmd']
    @vid = @cgi['vid'].to_i
    @login = Login.new(@cgi)
  end

  def run
    case @cmd
    when 'vils'
      handle_vils
    when 'players'
      handle_players
    when 'log'
      handle_log
    when 'events'
      handle_events
    when 'vil', 'info'
      handle_vil
    else
      print "Content-Type: application/json; charset=UTF-8\nStatus: 400 Bad Request\n\n"
      print JSON.generate({ 'error' => 'Invalid or missing cmd parameter' })
    end
  rescue => e
    print "Content-Type: text/plain; charset=UTF-8\nStatus: 500 Internal Server Error\n\n"
    print "Internal Server Error:\n"
    print "#{e.class}: #{e.message}\n"
    print e.backtrace.join("\n")
  end

  private

  # 0. 個別の村の情報を JSON で取得
  def handle_vil
    if @vid <= 0
      print "Content-Type: application/json; charset=UTF-8\nStatus: 400 Bad Request\n\n"
      print JSON.generate({ 'error' => 'Invalid or missing vid parameter' })
      return
    end

    vild = nil
    vldb = PStore.new('db/vil.db')
    vldb.transaction(true) do
      if vldb.root?("root#{@vid}")
        vild = vldb["root#{@vid}"]
      end
    end

    if !vild
      print "Content-Type: application/json; charset=UTF-8\nStatus: 404 Not Found\n\n"
      print JSON.generate({ 'error' => 'Village not found' })
      return
    end

    # 詳細DBから現在の進行情報を取得
    detail_data = {}
    detail_db_path = "db/vil#{(@vid - 1) / 100}/#{@vid}.db"
    if File.exist?(detail_db_path)
      begin
        detail_db = PStore.new(detail_db_path)
        detail_db.transaction(true) do
          vil_obj = detail_db['root']
          if vil_obj
            detail_data = {
              'date' => vil_obj.date,
              'night' => vil_obj.night,
              'entry_max' => vil_obj.entry_max,
              'entry_min' => vil_obj.entry_min,
              'night_commit' => vil_obj.night_commit,
              'open_skill' => vil_obj.open_skill,
              'death_defeat' => vil_obj.death_defeat,
              'update_time' => vil_obj.update_time,
              'survivors' => vil_obj.players.values.count { |p| p.dead == 0 }
            }
          end
        end
      rescue
        # 読み込み失敗時は無視
      end
    end

    vil_info = {
      'vid' => vild['vid'],
      'name' => vild['name'],
      'sname' => vild['sname'],
      'state' => vild['state'],
      'player_num' => vild['player_num'],
      'composition' => vild['composition'],
      'dummy' => vild['dummy'],
      'open_id' => vild['open_id'],
      'card' => vild['card'],
      'char' => vild['char'],
      'start_hour' => vild['start_hour'],
      'start_min' => vild['start_min'],
      'period' => vild['period'],
      'night_period' => vild['night_period'],
      'life_period' => vild['life_period'],
      
      # 詳細情報
      'date' => detail_data['date'] || 0,
      'night' => detail_data['night'] || false,
      'entry_max' => detail_data['entry_max'] || vild['player_num'],
      'entry_min' => detail_data['entry_min'] || vild['player_num'],
      'night_commit' => detail_data['night_commit'] || false,
      'open_skill' => detail_data['open_skill'] || false,
      'death_defeat' => detail_data['death_defeat'] || false,
      'update_time' => detail_data['update_time'] || 0,
      'survivors' => detail_data['survivors'] || 0
    }

    print "Content-Type: application/json; charset=UTF-8\n\n"
    print JSON.generate(vil_info)
  end

  # 1. 村一覧を JSON で取得
  def handle_vils
    vils = []
    
    # フィルタ条件の抽出
    state_filter = @cgi['state'] || @cgi['status']
    filter_type = nil
    if state_filter && !state_filter.empty?
      case state_filter.downcase
      when '0', '募集中', 'recruiting'
        filter_type = :recruiting
      when '1', '進行中', 'playing', 'active'
        filter_type = :playing
      when '2', '3', '決着', 'finished', 'ended', 'done', 'over'
        filter_type = :finished
      end
    end

    vldb = PStore.new('db/vil.db')
    vldb.transaction(true) do
      if vldb.root?('recent_vid')
        recent_vid = vldb['recent_vid'].to_i
        1.upto(recent_vid) do |i|
          next unless vldb.root?("root#{i}")
          vild = vldb["root#{i}"]
          
          state_val = vild['state'].to_i
          if filter_type
            case filter_type
            when :recruiting
              next if state_val != 0
            when :playing
              next if state_val != 1
            when :finished
              next if state_val < 2
            end
          end
          
          # 各村の進行状況（現在の日付や生存人数など）を詳細DBから取得
          detail_data = {}
          detail_db_path = "db/vil#{(i - 1) / 100}/#{i}.db"
          if File.exist?(detail_db_path)
            begin
              detail_db = PStore.new(detail_db_path)
              detail_db.transaction(true) do
                vil_obj = detail_db['root']
                if vil_obj
                  detail_data = {
                    'date' => vil_obj.date,
                    'night' => vil_obj.night,
                    'survivors' => vil_obj.players.values.count { |p| p.dead == 0 }
                  }
                end
              end
            rescue
              # 読み込み失敗時は無視
            end
          end

          vils << {
            'vid' => vild['vid'],
            'name' => vild['name'],
            'sname' => vild['sname'],
            'state' => vild['state'], # 0=募集中, 1=進行中, 2=市民勝利, 3=人狼勝利
            'player_num' => vild['player_num'],
            'composition' => vild['composition'],
            'dummy' => vild['dummy'],
            'date' => detail_data['date'] || 0,
            'night' => detail_data['night'] || false,
            'survivors' => detail_data['survivors'] || 0
          }
        end
      end
    end
    
    print "Content-Type: application/json; charset=UTF-8\n\n"
    print JSON.generate(vils)
  end

  # 2. 参加者一覧を JSON で取得
  def handle_players
    if @vid <= 0
      print "Content-Type: application/json; charset=UTF-8\nStatus: 400 Bad Request\n\n"
      print JSON.generate({ 'error' => 'Invalid or missing vid parameter' })
      return
    end

    db_path = "db/vil#{(@vid - 1) / 100}/#{@vid}.db"
    if !File.exist?(db_path)
      print "Content-Type: application/json; charset=UTF-8\nStatus: 404 Not Found\n\n"
      print JSON.generate({ 'error' => 'Village not found' })
      return
    end

    players_list = []
    db = PStore.new(db_path)
    db.transaction(true) do
      vil = db['root']
      if vil
        # ゲーム終了している場合は全員の役職を開示
        game_over = vil.state >= 2
        
        current_player = @login.login ? vil.player(@login) : nil
        vil.players.each do |userid, player|
          role_name = nil
          if game_over || (current_player && current_player.num_id == player.num_id)
            role_name = Skill.skills[player.sid].name
          end

          # 投票済みフラグ（生存者のみ）
          voted = player.dead == 0 ? (player.vote != -1) : nil
          acted = (player.dead == 0 && current_player && current_player.num_id == player.num_id) ? (player.target != -1) : nil

          players_list << {
            'userid' => userid,
            'name' => player.name,
            'dead' => player.dead, # 0=生存, 1=死亡, 2=無残, 3=処刑
            'role' => role_name,   # 進行中は null
            'num_id' => player.num_id,
            'voted' => voted,
            'acted' => acted
          }
        end
      end
    end

    print "Content-Type: application/json; charset=UTF-8\n\n"
    print JSON.generate(players_list)
  end

  # 3. チャットログをテキストで取得
  def handle_log
    if @vid <= 0
      print "Content-Type: text/plain; charset=UTF-8\nStatus: 400 Bad Request\n\n"
      print "Error: Invalid or missing vid parameter"
      return
    end

    date_param = @cgi['date']
    log_dir = "db/log#{(@vid - 1) / 100}"

    since_time = nil
    since_param = @cgi['since'] || @cgi['time']
    if since_param && !since_param.empty?
      begin
        since_time = Time.parse(since_param)
      rescue
      end
    end
    
    if !File.exist?(log_dir)
      print "Content-Type: text/plain; charset=UTF-8\nStatus: 404 Not Found\n\n"
      print "Error: Village logs not found"
      return
    end

    # 村の進行状態とログインプレイヤー情報を取得
    vil_state = 0
    open_skill = false
    current_player = nil
    db_path = "db/vil#{(@vid - 1) / 100}/#{@vid}.db"
    if File.exist?(db_path)
      begin
        db = PStore.new(db_path)
        db.transaction(true) do
          vil = db['root']
          if vil
            vil_state = vil.state
            open_skill = vil.open_skill
            if @login.login
              current_player = vil.player(@login)
            end
          end
        end
      rescue
      end
    end

    log_files = []
    if date_param && date_param != 'all'
      file_path = "#{log_dir}/#{@vid}_#{date_param.to_i}.html"
      log_files << [date_param.to_i, file_path] if File.exist?(file_path)
    else
      # すべての日付のログを昇順で取得
      Dir.glob("#{log_dir}/#{@vid}_*.html").each do |file|
        if file =~ /#{@vid}_(\d+)\.html$/
          log_files << [$1.to_i, file]
        end
      end
      log_files.sort_by! { |d, f| d }
    end

    if log_files.empty?
      print "Content-Type: text/plain; charset=UTF-8\nStatus: 404 Not Found\n\n"
      print "Error: Logs not found for specified date"
      return
    end

    print "Content-Type: text/plain; charset=UTF-8\n\n"

    last_msg_time = nil
    log_files.each do |day, path|
      print "=== #{day}日目 ===\n"
      File.open(path, "r:utf-8") do |f|
        f.each_line do |line|
          line.strip!
          next if line.empty?

          # コメントタグ（type_code と target_id）の判定
          if line =~ /^<!--([a-z]+)(\d*)-->/
            type_code = $1
            target_id = $2.to_i

            # ゲーム進行中のフィルタリング（終了後は全て見せる）
            if vil_state < 2
              case type_code
              when 'think'
                next if current_player.nil?
                next if current_player.num_id != target_id
              when 'whisperhowl'
                next if vil_state == 0
                # ささやきが見えないプレイヤーは「わおーん」に置き換える
                if current_player.nil? || (!current_player.can_whisper && (!open_skill || current_player.dead == 0))
                  # タイムスタンプの抽出を試みる
                  time_str = line =~ /<span class="time">(.*?)<\/span>/ ? $1 : ""
                  msg_time = nil
                  begin
                    msg_time = Time.parse(time_str)
                  rescue
                  end
                  if msg_time
                    last_msg_time = msg_time
                    if since_time && msg_time < since_time
                      next
                    end
                  end
                  print "[#{time_str}] [システム] 狼の遠吠え: わおーん\n"
                  next
                end
              when 'whisper'
                next if vil_state == 0
                next if current_player.nil?
                next if !current_player.can_whisper && (!open_skill || current_player.dead == 0)
              when 'groan'
                next if vil_state == 0
                next if current_player.nil?
                next if current_player.dead == 0
              when 'sprit' # 霊能者の霊界メッセージ
                next if vil_state == 0
                next if current_player.nil?
                next if current_player.sid != 3
              when 'fanatic' # 狂信者メッセージ
                next if vil_state == 0
                next if current_player.nil?
                next if !current_player.can_whisper && current_player.sid != 9
              end
            end
          end

          # 1. 通常発言、独り言、ささやき、うめき等のテーブル形式
          if line =~ /^<!--(say|think|whisper|groan|fanatic|spirit|whisperhowl)\d*-->\s*<table class="message">.*?target="_blank">(.*?)<\/a>.*?<span class="time">(.*?)<\/span>.*?<div class="mes_(say|think|whisper|groan|fanatic|spirit|whisperhowl)_body1">(.*?)<\/div>.*?<\/table>/
            type_code = $1
            speaker = $2
            time_str = $3
            content_html = $5

            text_content = content_html.gsub(/<br\s*\/?>/i, "\n").gsub(/<[^>]+>/, '')
            text_content = text_content.gsub(/&lt;/, '<').gsub(/&gt;/, '>').gsub(/&amp;/, '&').gsub(/&quot;/, '"')

            type_label = case type_code
                         when 'think' then ' (独り言)'
                         when 'whisper', 'whisperhowl' then ' (ささやき)'
                         when 'groan' then ' (うめき)'
                         when 'fanatic' then ' (狂信ささやき)'
                         when 'spirit' then ' (死者ささやき)'
                         else ''
                         end

            msg_time = nil
            begin
              msg_time = Time.parse(time_str)
            rescue
            end
            if msg_time
              last_msg_time = msg_time
              if since_time && msg_time < since_time
                next
              end
            end

            # ゲーム進行中のwhisperhowlは発言者も匿名化して出力（二重防御）
            if vil_state < 2 && type_code == 'whisperhowl' &&
               (current_player.nil? || (!current_player.can_whisper && (!open_skill || current_player.dead == 0)))
              print "[#{time_str}] [システム] 狼の遠吠え: わおーん\n"
            else
              print "[#{time_str}] #{speaker}#{type_label}: #{text_content}\n"
            end

          # 1b. 狼の遠吠え (直接書き出されている場合)
          elsif line =~ /<table class="message">.*?<td colspan="2" class="howl">狼の遠吠え<\/td>.*?<div class="mes_whisper_body1">(.*?)<\/div>.*?<\/table>/
            content = $1
            if since_time && last_msg_time && last_msg_time < since_time
              next
            end
            print "[システム] 狼の遠吠え: #{content}\n"

          # 2. アナウンス（システムメッセージ）
          elsif line =~ /^<!--(?:say|think|whisper|groan|fanatic|spirit|whisperhowl)?\d*-->\s*<div class="announce.*?">(.*?)<\/div>/
            content_html = $1
            text_content = content_html.gsub(/<br\s*\/?>/i, "\n").gsub(/<[^>]+>/, '')
            text_content = text_content.gsub(/&lt;/, '<').gsub(/&gt;/, '>').gsub(/&amp;/, '&').gsub(/&quot;/, '"')
            
            if since_time && last_msg_time && last_msg_time < since_time
              next
            end
            print "[システム]: #{text_content}\n"
          end

          # 3. 時間アナウンスや進行ブロック
          if line =~ /<(?:div|span) class="(?:time_announce|alllog_announce)">(.*?)<\/(?:div|span)>/
            content_html = $1
            text_content = content_html.gsub(/<[^>]+>/, '').strip

            if since_time && last_msg_time && last_msg_time < since_time
              next
            end
            print "[進行]: #{text_content}\n"
          end
        end
      end
      print "\n"
    end
  end

  # 5. ロングポーリングによるイベントストリーム取得
  def handle_events
    if @vid <= 0
      print "Content-Type: application/json; charset=UTF-8\nStatus: 400 Bad Request\n\n"
      print ({ error: "Invalid or missing vid parameter" }.to_json)
      return
    end

    since_id = (@cgi['since'] || 0).to_i
    db_path = "db/vil#{(@vid - 1) / 100}/#{@vid}.db"
    
    unless File.exist?(db_path)
      print "Content-Type: application/json; charset=UTF-8\nStatus: 404 Not Found\n\n"
      print ({ error: "Village not found" }.to_json)
      return
    end

    # ロングポーリングループ（最大15秒、1秒スリープ）
    max_wait = 15
    start_time = Time.now
    new_events = []
    vil_state = 0
    open_skill = false
    current_player = nil

    while (Time.now - start_time) < max_wait
      begin
        db = PStore.new(db_path)
        db.transaction(true) do
          vil = db['root']
          if vil
            vil_state = vil.state
            open_skill = vil.open_skill
            if @login.login
              current_player = vil.player(@login)
            end
            
            all_events = vil.events
            new_events = all_events.select { |e| e[:id] > since_id }
          end
        end
      rescue => e
        # Ignore read errors and retry
      end

      break unless new_events.empty?
      sleep 1.0
    end

    # 閲覧権限によるイベントフィルタリング
    filtered_events = []
    new_events.each do |e|
      keep = true
      masked_content = nil

      if vil_state < 2
        case e[:type_code]
        when 'think'
          if current_player.nil? || current_player.num_id != e[:speaker_id]
            keep = false
          end
        when 'whisper', 'whisperhowl'
          if current_player.nil? || (!current_player.can_whisper && (!open_skill || current_player.dead == 0))
            if e[:type_code] == 'whisperhowl'
              masked_content = "狼の遠吠え: わおーん"
            else
              keep = false
            end
          end
        when 'groan'
          if current_player.nil? || current_player.dead == 0
            keep = false
          end
        when 'spirit'
          if current_player.nil? || current_player.sid != 3
            keep = false
          end
        when 'fanatic'
          if current_player.nil? || (!current_player.can_whisper && current_player.sid != 9)
            keep = false
          end
        end
      end

      if keep
        event_copy = e.dup
        if masked_content
          # ささやきをマスクする際は内容だけでなく発言者情報も匿名化する
          # （誰が発言したかを推測できないよう speaker / speaker_id も隠す）
          event_copy[:content]    = masked_content
          event_copy[:speaker]    = 'システム'
          event_copy[:speaker_id] = nil
        end
        # 自分の発言フラグの付与
        if current_player && e[:speaker_id] == current_player.num_id
          event_copy[:is_mine] = true
        else
          event_copy[:is_mine] = false
        end
        filtered_events << event_copy
      end
    end

    print "Content-Type: application/json; charset=UTF-8\n\n"
    print filtered_events.to_json
  end
end

if __FILE__ == $0
  Api.new.run
end
