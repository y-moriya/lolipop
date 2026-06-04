# -*- coding: utf-8 -*-
require 'net/http'
require 'uri'
require 'json'
require 'yaml'
require 'thread'
require 'cgi'
require_relative 'game_state'
require_relative 'llm_client'
require_relative 'prompt_manager'
require_relative 'learning_system'

# ロードパスに CGI 側のパスを追加して Charset を require できるようにする
$LOAD_PATH.unshift(File.expand_path('../../public_html/aiwolf', __dir__))
begin
  require 'charset'
rescue LoadError
  # ロードできない場合はテスト環境外とみなす
end

module AnmanAI
  STDOUT.sync = true
  STDERR.sync = true

  class Client
    def initialize(config_path, root_dir)
      @root_dir = root_dir
      @config = YAML.load_file(config_path)
      @url = @config['server']['url']
      @vid = @config['server']['vid']
      @userid = @config['user']['userid']
      @password = @config['user']['password']
      
      @cookie = nil
      @game_state = GameState.new(@userid)
      @llm = LLMClient.new(@config)
      @prompts = PromptManager.new(root_dir)
      @learning = LearningSystem.new(root_dir, @llm)
      
      @voted_today = {}    # { day => bool }
      @acted_tonight = {}  # { day => bool }
      @whispered_tonight = {} # { day => bool }
      @last_say_time = Time.at(0)
      @last_chat_logs_size = 0
      
      @reflected_and_greeting = false
      @epilogue_start_time = nil
    end
    
    # 接続・ログイン (Cookieの取得)
    def login!
      uri = URI.parse("#{@url}/aiwolf/index.cgi")
      req = Net::HTTP::Post.new(uri.path)
      req.set_form_data('cmd' => 'login', 'userid' => @userid, 'pass' => @password)
      
      begin
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') { |http| http.request(req) }
        if res.code == '200' || res.code == '302'
          set_cookie_header = res['Set-Cookie']
          if set_cookie_header
            @cookie = set_cookie_header.split(';').first
          end
          puts "[System DEBUG] Logged in successfully to #{@url} as #{@userid}."
          puts "[System DEBUG] Set-Cookie header: #{set_cookie_header.inspect}"
          puts "[System DEBUG] Parsed @cookie: #{@cookie.inspect}"
          true
        else
          raise "Login failed: #{res.code} - #{res.body}"
        end
      rescue => e
        raise "Connection failed during login: #{e.message}"
      end
    end
    
    # POST送信ヘルパー
    def post(params)
      uri = URI.parse("#{@url}/aiwolf/index.cgi")
      req = Net::HTTP::Post.new(uri.path)
      req['Cookie'] = @cookie if @cookie
      req.set_form_data(params.merge('vid' => @vid.to_s))
      
      begin
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') { |http| http.request(req) }
        if res
          body_snippet = res.body ? res.body[0...300].gsub(/\s+/, ' ') : ''
          puts "[System DEBUG] Post action #{params['cmd']} response: #{res.code} - #{body_snippet}..."
        else
          puts "[System DEBUG] Post action #{params['cmd']} response: nil"
        end
        res
      rescue => e
        puts "[System] Error posting action #{params['cmd']}: #{e.message}"
        nil
      end
    end
    
    # GET送信ヘルパー
    def get_api(params)
      uri = URI.parse("#{@url}/aiwolf/api.cgi")
      uri.query = URI.encode_www_form(params.merge('vid' => @vid.to_s))
      req = Net::HTTP::Get.new(uri)
      req['Cookie'] = @cookie if @cookie
      
      begin
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') { |http| http.request(req) }
        res.body.force_encoding('UTF-8') if res && res.body
        res
      rescue => e
        puts "[System] Error fetching API #{params['cmd']}: #{e.message}"
        nil
      end
    end
    
    # 募集中の村を監視し、自動でエントリーする
    def auto_entry_loop!
      puts "[System] Scoping recruiting villages..."
      loop do
        begin
          res = get_api('cmd' => 'vils', 'state' => 'recruiting')
          if res && res.code == '200'
            vils = JSON.parse(res.body)
            recruiting_vil = vils.find { |v| v['state'].to_i == 0 }
            if recruiting_vil
              @vid = recruiting_vil['vid'].to_i
              puts "[System] Found recruiting village: #{@vid} (#{recruiting_vil['name']})"
              
              if entry_to_village!
                puts "[System] Successfully entered village #{@vid}."
                break
              else
                puts "[System] Failed to enter village. Retrying..."
              end
            end
          end
        rescue => e
          puts "[System Error] Error in auto_entry_loop: #{e.message}"
        end
        sleep 5
      end
    end

    # キャラクターを選択し、LLMによる自己紹介を添えて入村する
    def entry_to_village!
      res_vil = get_api('cmd' => 'vil')
      return false unless res_vil && res_vil.code == '200'
      vil_info = JSON.parse(res_vil.body)
      char_set_id = vil_info['char'].to_i
      
      res_players = get_api('cmd' => 'players')
      return false unless res_players && res_players.code == '200'
      players_json = JSON.parse(res_players.body)
      
      if players_json.any? { |p| p['userid'] == @userid }
        return true
      end
      
      charset = Charset.charsets[char_set_id] rescue nil
      return false unless charset
      
      used_names = players_json.map { |p| p['name'] }
      
      available_pids = []
      charset.char_names.each_with_index do |name, pid|
        next if pid == 0
        unless used_names.include?(name)
          available_pids << pid
        end
      end
      
      chosen_pid = available_pids.sample || rand(1...charset.char_names.size)
      chosen_char_name = charset.char_names[chosen_pid]
      
      puts "[System] Chosen character: #{chosen_char_name} (ID: #{chosen_pid})"
      
      greeting = generate_character_greeting(chosen_char_name)
      puts "[System] Generated entry greeting: \"#{greeting}\""
      
      vil_pass = @config.dig('server', 'pass') || ''
      post(
        'cmd' => 'entry',
        'pid' => chosen_pid.to_s,
        'pass' => vil_pass,
        'message' => greeting,
        'j_data' => 'あ'
      )
      
      sleep 1.0
      res_players = get_api('cmd' => 'players')
      if res_players && res_players.code == '200'
        players_json = JSON.parse(res_players.body)
        return players_json.any? { |p| p['userid'] == @userid }
      end
      
      false
    end

    def generate_character_greeting(char_name)
      system_prompt = "あなたは人狼ゲームのキャラクター「#{char_name}」です。そのキャラクターになりきって、入村時の挨拶メッセージを1行で作成してください。挨拶以外のメタ発言や余計な解説、マークダウン記法（ダブルクォーテーションや```等）は一切含めてはいけません。"
      user_prompt = "人狼ゲームの村の集会所に入りました。他のプレイヤーたちに、自己紹介を兼ねて挨拶してください。"
      
      begin
        @last_say_time = Time.now
        response = @llm.chat(system_prompt, user_prompt, temperature: 0.8)
        response.gsub!(/^["'「]+/, "")
        response.gsub!(/["'」]+$/, "")
        response.strip
      rescue => e
        puts "[System Error] Failed to generate greeting: #{e.message}"
        "よろしくお願いします。"
      end
    end
    
    # ゲーム情報の初期化 (cmd=playersから役職やプレイヤー名のマッピング)
    def init_game_state!
      res_players = get_api('cmd' => 'players')
      unless res_players && res_players.code == '200'
        raise "Failed to initialize game state: Cannot fetch players list."
      end

      players_json = JSON.parse(res_players.body)
      current_player = players_json.find { |p| p['userid'] == @userid }
      
      @game_state.init_players(players_json, current_player)
      puts "[System] Game state initialized. Your role: #{@game_state.my_role}."
    end
    
    # メインループ
    def start_loop!
      puts "[System] Starting event monitoring loop..."
      events_queue = Queue.new
      since_id = 0
      
      # 1. バックグラウンドでイベントをロングポーリング受信するスレッド
      event_thread = Thread.new do
        loop do
          begin
            res = get_api('cmd' => 'events', 'since' => since_id.to_s)
            if res && res.code == '200'
              events = JSON.parse(res.body)
              events.each do |e|
                events_queue << e
                since_id = [since_id, e['id'].to_i].max
              end
            end
          rescue => e
            puts "[Event Thread Error] #{e.class} - #{e.message}"
          end
          sleep 1
        end
      end
      
      # 2. メインの監視・自律意思決定制御ループ (メインスレッド)
      last_vil_check = Time.at(0)
      update_time = 0
      game_state_val = 1 # 1=進行中
      
      loop do
        begin
          # キューから溜まっているイベントをすべて処理して GameState を更新
          has_new_events = false
          while !events_queue.empty?
            e = events_queue.pop(true)
            puts "[DEBUG] Event: ID=#{e['id']}, type=#{e['type']}, type_code=#{e['type_code']}"
            @game_state.process_event(e)
            has_new_events = true
            
            # ゲーム終了の検知などは即座に行う
            handle_event_action_instantly(e)
          end
          
          # 3秒に1回、村の全体ステータス (残り時間など) を API から取得・同期
          if Time.now - last_vil_check >= 3
            res_vil = get_api('cmd' => 'vil')
            if res_vil && res_vil.code == '200'
              vil_info = JSON.parse(res_vil.body)
              update_time = vil_info['update_time'].to_i
              game_state_val = vil_info['state'].to_i
              
              @game_state.current_day = vil_info['date'].to_i
              @game_state.is_night = vil_info['night']
            end
            last_vil_check = Time.now
          end
          
          # ゲームが終了（決着）した場合は感想戦モードに入る
          if game_state_val >= 2
            unless @reflected_and_greeting
              puts "[System] Game is over. Running reflection and posting epilogue chat..."
              trigger_reflection_and_epilogue(game_state_val)
              @reflected_and_greeting = true
              @epilogue_start_time = Time.now
            end
            
            # 感想戦開始からのタイムアウト判定 (デフォルト3600秒)
            epilogue_timeout = @config.dig('server', 'epilogue_timeout') || 3600
            if Time.now - @epilogue_start_time >= epilogue_timeout
              puts "[System] Epilogue session completed. Exiting client..."
              break
            end
            
            # 感想戦中も、他人の新着メッセージがあれば反応発言するか、一定時間発言がなければ自発的に発言する
            time_since_last_say = Time.now - @last_say_time
            if time_since_last_say >= 15
              current_chat_size = @game_state.chat_logs.size
              if (current_chat_size > @last_chat_logs_size) || (time_since_last_say >= 30)
                check_and_say_epilogue
                @last_chat_logs_size = current_chat_size
              end
            end
            
            sleep 1
            next
          end
          
          # 昼夜の状態に応じた自律アクション判断
          day = @game_state.current_day
          remain_sec = update_time - Time.now.to_i
          
          # 自分が死亡しているか確認
          my_player = @game_state.players[@game_state.my_name]
          is_dead = my_player && my_player[:dead] != 0
          
          # 1. 自律的・反応的な発言・思考発信の判定 (昼夜、生存死亡を問わず実行)
          time_since_last_say = Time.now - @last_say_time
          if time_since_last_say >= 15
            current_chat_size = @game_state.chat_logs.size
            # 条件A: 新しいチャットがあった（反応発言）
            # 条件B: 前回の発言から30秒経過しており、誰も発言していない（能動的発言）
            if (current_chat_size > @last_chat_logs_size) || (time_since_last_say >= 30)
              check_and_say
              @last_chat_logs_size = current_chat_size
            end
          end
          
          if @game_state.is_night
            # 夜フェーズ (生存時のみアクション可能)
            unless is_dead
              # 1. 人狼のささやき（夜の初めに1回）
              if @game_state.my_role == "人狼" && !@whispered_tonight[day]
                trigger_whisper
              end
              
              # 2. 夜アクションの実行（占い、人狼襲撃、護衛など）
              if !@acted_tonight[day]
                trigger_night_action
              end
            end
          else
            # 昼フェーズ
            # 更新時間が近づいたら投票を行う (残り時間15秒以下、かつ未投票、生存時のみ)
            unless is_dead
              if !@voted_today[day] && remain_sec > 0 && remain_sec <= 15
                puts "[System] Deadline approaching (#{remain_sec}s remaining). Triggering vote."
                trigger_vote
              end
            end
          end
          
        rescue => e
          puts "[System Error] Error in main loop: #{e.class} - #{e.message}"
          puts e.backtrace.join("\n")
        end
        sleep 1
      end
      
      # ループを抜けたらイベント受信スレッドを停止
      Thread.kill(event_thread) rescue nil
    end
    
    # 勝敗決定（ゲーム終了）の即時検知
    def handle_event_action_instantly(e)
      if e['type'] == 'system' && e['type_code'] == 'announce' && e['content'].include?("の勝利です！")
        unless @reflected_and_greeting
          puts "[System] Game end announcement detected from events: #{e['content']}"
          # メインループ側の感想戦判定に任せるが、フラグ更新や処理を安全に進める
        end
      end
    end
    
    # 自律的・反応的な発言・思考発信処理（生存/死亡、昼/夜に応じてメッセージ種別を切り替える）
    def check_and_say
      return if @game_state.current_day < 1
      
      my_player = @game_state.players[@game_state.my_name]
      is_dead = my_player && my_player[:dead] != 0
      
      # 昼か夜か
      is_night = @game_state.is_night
      
      # メッセージタイプの決定
      # - 死亡時: groan (うめき)
      # - 生存時かつ夜: think (独り言)
      # - 生存時かつ昼: say (通常発言)
      msg_type = if is_dead
                   'groan'
                 elsif is_night
                   'think'
                 else
                   'say'
                 end
      
      puts "\n[Thinking] Evaluating response (is_dead: #{is_dead}, is_night: #{is_night}, msg_type: #{msg_type})..."
      
      vars = {
        'current_day' => @game_state.current_day,
        'my_name' => @game_state.my_name,
        'my_role' => @game_state.my_role,
        'surviving_players' => @game_state.surviving_players_list,
        'dead_players' => @game_state.dead_players_list,
        'my_reasoning_notes' => @game_state.my_reasoning_notes,
        'chat_logs' => @game_state.formatted_chat_logs,
        'learning_memory' => @learning.load_memory_text,
        'role_instructions' => @prompts.load_camp_prompt(camp_from_role)
      }
      
      # 前回の発言から28秒以上経過している場合は、能動的発信（沈黙タイムアウト）とみなす
      time_since_last_say = Time.now - @last_say_time
      is_active_trigger = (time_since_last_say >= 28)
      
      system_prompt = "あなたは人狼ゲームのプレイヤー「#{@game_state.my_name}」です。必ず指定されたJSONフォーマットで回答してください。JSON以外の文章は一切含めてはいけません。"
      
      case msg_type
      when 'groan'
        system_prompt += "【重要】あなたは既に死亡しています。現在は霊界（あの世）から生存者の様子を見守っている状態です。他の死者プレイヤーと会話するために「うめき（霊界チャット）」を投稿してください。うめき声らしく（例：『ううっ…』『あの時こうすべきだった…』など）、しかし推理や感想を含めて発言してください。"
        if is_active_trigger
          system_prompt += "【重要】しばらくあなたの発言（うめき）がありません。霊界から何か独り言や、生存者へのうめき声を必ず message に記述して送信してください（message を空にしないでください）。"
        end
      when 'think'
        system_prompt += "【重要】現在は夜フェーズです。あなたは生き残っていますが、夜間は他のプレイヤーと直接会話することはできません。そこで、今夜の行動方針や、今日1日の振り返り、誰が人狼かといった推理、今後の戦略について、頭の中で「独り言（think）」としてつぶやいてください。独り言なので他人に聞かれることはありません。"
        if is_active_trigger
          system_prompt += "【重要】しばらくあなたの思考発信（独り言）がありません。今夜の戦略や疑問、推理など、頭の中の思考を必ず message に記述してください（message を空にしないでください）。"
        end
      when 'say'
        # 昼フェーズの通常発言
        if is_active_trigger
          system_prompt += "【重要】現在、議論が少し停滞しているか、前回の発言から時間が空いています。生存アピールや、疑わしい人についての簡単な疑問、あるいは議論を活性化させるための雑談などを必ず message に記述して発言してください（message を空にしないでください）。"
        end
      end
      
      user_prompt = @prompts.build_prompt('say', vars)
      
      begin
        response = @llm.chat(system_prompt, user_prompt)
        clean_res = response.gsub(/^```json\s*/, "").gsub(/```\s*$/, "").strip
        parsed = JSON.parse(clean_res)
        
        if parsed['reasoning_update'] && !parsed['reasoning_update'].empty?
          @game_state.my_reasoning_notes = parsed['reasoning_update']
        end
        
        msg = parsed['message']
        if msg && !msg.empty?
          case msg_type
          when 'groan'
            puts "[Action] AI decided to groan (dead chat): \"#{msg}\""
            post('cmd' => 'msg', 'message' => msg, 'groan' => 'on', 'j_data' => 'a')
          when 'think'
            puts "[Action] AI decided to think (monologue): \"#{msg}\""
            post('cmd' => 'msg', 'message' => msg, 'think' => 'on', 'j_data' => 'a')
          when 'say'
            puts "[Action] AI decided to say: \"#{msg}\""
            post('cmd' => 'msg', 'message' => msg, 'j_data' => 'a')
          end
          @last_say_time = Time.now
        else
          puts "[Action] AI decided to skip speaking (pass)."
        end
      rescue => e
        puts "[System Error] Failed in check_and_say: #{e.message}"
      end
    end
    
    # 投票行動の決定・実行
    def trigger_vote
      day = @game_state.current_day
      return if @voted_today[day]
      
      puts "\n[Thinking] Deciding who to vote for today..."
      
      vars = {
        'current_day' => day,
        'my_name' => @game_state.my_name,
        'my_role' => @game_state.my_role,
        'surviving_players' => @game_state.surviving_players_list,
        'my_reasoning_notes' => @game_state.my_reasoning_notes,
        'chat_logs' => @game_state.formatted_chat_logs,
        'learning_memory' => @learning.load_memory_text,
        'role_instructions' => @prompts.load_camp_prompt(camp_from_role)
      }
      
      system_prompt = "あなたは人狼ゲームのプレイヤーです。必ず指定されたJSONフォーマットで回答してください。JSON以外の文章は一切含めてはいけません。"
      user_prompt = @prompts.build_prompt('vote', vars)
      
      begin
        response = @llm.chat(system_prompt, user_prompt, temperature: 0.2)
        clean_res = response.gsub(/^```json\s*/, "").gsub(/```\s*$/, "").strip
        parsed = JSON.parse(clean_res)
        
        target_name = parsed['vote_target']
        target_player = @game_state.players[target_name]
        
        if target_player && target_player[:dead] == 0 && target_name != @userid
          puts "[Action] AI decided to vote for: #{target_name} (ID: #{target_player[:num_id]})"
          post(
            'cmd' => 'vote', 
            'vote_id' => target_player[:num_id].to_s, 
            'set_date' => day.to_s
          )
          @voted_today[day] = true
        else
          puts "[Action] AI target name '#{target_name}' is invalid or dead. Fallback to random voting."
          fallback_target = @game_state.players.select { |name, p| p[:dead] == 0 && name != @userid }.values.sample
          if fallback_target
            post(
              'cmd' => 'vote', 
              'vote_id' => fallback_target[:num_id].to_s, 
              'set_date' => day.to_s
            )
            @voted_today[day] = true
          end
        end
      rescue => e
        puts "[System Error] Failed in trigger_vote: #{e.message}"
      end
    end
    
    # 夜アクション（占い・護衛・人狼ささやきなど）の実行
    def trigger_night_action
      day = @game_state.current_day
      
      case @game_state.my_role
      when "占い師"
        puts "\n[Thinking] Deciding who to scan tonight..."
        vars = {
          'current_day' => day,
          'my_name' => @game_state.my_name,
          'my_role' => @game_state.my_role,
          'surviving_players' => @game_state.surviving_players_list,
          'action_results' => @game_state.formatted_action_results,
          'my_reasoning_notes' => @game_state.my_reasoning_notes,
          'chat_logs' => @game_state.formatted_chat_logs,
          'learning_memory' => @learning.load_memory_text,
          'role_instructions' => @prompts.load_camp_prompt(camp_from_role)
        }
        
        system_prompt = "あなたは人狼ゲームの占い師です。必ず指定されたJSONフォーマットで回答してください。JSON以外の文章は一切含めてはいけません。"
        user_prompt = @prompts.build_prompt('fortune', vars)
        
        begin
          response = @llm.chat(system_prompt, user_prompt, temperature: 0.2)
          clean_res = response.gsub(/^```json\s*/, "").gsub(/```\s*$/, "").strip
          parsed = JSON.parse(clean_res)
          
          target_name = parsed['fortune_target']
          target_player = @game_state.players[target_name]
          
          if target_player && target_player[:dead] == 0 && target_name != @userid
            puts "[Action] AI decided to scan (fortune): #{target_name} (ID: #{target_player[:num_id]})"
            post(
              'cmd' => 'skill',
              'target_id' => target_player[:num_id].to_s,
              'set_date' => day.to_s
            )
            @acted_tonight[day] = true
            @game_state.action_results << "#{day}日目夜: #{target_name} を占い対象としてセットしました。"
          else
            fallback_target = @game_state.players.select { |name, p| p[:dead] == 0 && name != @userid }.values.sample
            if fallback_target
              puts "[Action] Fallback scanning (fortune): (ID: #{fallback_target[:num_id]})"
              post(
                'cmd' => 'skill',
                'target_id' => fallback_target[:num_id].to_s,
                'set_date' => day.to_s
              )
              @acted_tonight[day] = true
            end
          end
        rescue => e
          puts "[System Error] Failed in trigger_night_action: #{e.message}"
        end
        
      when "人狼"
        puts "\n[Thinking] Deciding who to attack tonight..."
        vars = {
          'current_day' => day,
          'my_name' => @game_state.my_name,
          'my_role' => @game_state.my_role,
          'surviving_players' => @game_state.surviving_players_list,
          'my_reasoning_notes' => @game_state.my_reasoning_notes,
          'chat_logs' => @game_state.formatted_chat_logs,
          'learning_memory' => @learning.load_memory_text,
          'role_instructions' => @prompts.load_camp_prompt('werewolf')
        }
        
        system_prompt = "あなたは人狼です。今夜襲撃する市民を1人選択してください。必ず指定されたJSONフォーマットで回答してください。JSON以外の文章は一切含めてはいけません。"
        user_prompt = @prompts.build_prompt('fortune', vars).gsub("占い対象", "襲撃対象").gsub("fortune_target", "attack_target")
        
        begin
          response = @llm.chat(system_prompt, user_prompt, temperature: 0.2)
          clean_res = response.gsub(/^```json\s*/, "").gsub(/```\s*$/, "").strip
          parsed = JSON.parse(clean_res)
          
          target_name = parsed['attack_target'] || parsed['fortune_target']
          target_player = @game_state.players[target_name]
          
          if target_player && target_player[:dead] == 0 && target_name != @userid
            puts "[Action] AI decided to attack: #{target_name} (ID: #{target_player[:num_id]})"
            post(
              'cmd' => 'skill',
              'target_id' => target_player[:num_id].to_s,
              'set_date' => day.to_s
            )
            @acted_tonight[day] = true
          else
            targets = @game_state.players.select { |name, p| p[:dead] == 0 && name != @userid && !@game_state.werewolf_partners.include?(name) }
            fallback_target = targets.values.sample || @game_state.players.select { |name, p| p[:dead] == 0 && name != @userid }.values.sample
            if fallback_target
              puts "[Action] Fallback attacking: (ID: #{fallback_target[:num_id]})"
              post(
                'cmd' => 'skill',
                'target_id' => fallback_target[:num_id].to_s,
                'set_date' => day.to_s
              )
              @acted_tonight[day] = true
            end
          end
        rescue => e
          puts "[System Error] Failed in werewolf attack action: #{e.message}"
        end
      end
    end
    
    # 人狼のささやきの実行
    def trigger_whisper
      day = @game_state.current_day
      puts "\n[Thinking] Drafting werewolf whisper chat..."
      
      vars = {
        'current_day' => day,
        'my_name' => @game_state.my_name,
        'surviving_players' => @game_state.surviving_players_list,
        'werewolf_partners' => @game_state.werewolf_partners.join(", "),
        'my_reasoning_notes' => @game_state.my_reasoning_notes,
        'chat_logs' => @game_state.formatted_chat_logs,
        'learning_memory' => @learning.load_memory_text,
        'role_instructions' => @prompts.load_camp_prompt('werewolf')
      }
      
      system_prompt = "あなたは人狼です。必ず指定されたJSONフォーマットで回答してください。JSON以外の文章は一切含めてはいけません。"
      user_prompt = @prompts.build_prompt('whisper', vars)
      
      begin
        response = @llm.chat(system_prompt, user_prompt)
        clean_res = response.gsub(/^```json\s*/, "").gsub(/```\s*$/, "").strip
        parsed = JSON.parse(clean_res)
        
        if parsed['reasoning_update'] && !parsed['reasoning_update'].empty?
          @game_state.my_reasoning_notes = parsed['reasoning_update']
        end
        
        msg = parsed['message']
        if msg && !msg.empty?
          puts "[Action] AI decided to whisper: \"#{msg}\""
          post('cmd' => 'msg', 'message' => msg, 'whisper' => 'on', 'j_data' => 'a')
        end
        @whispered_tonight[day] = true
      rescue => e
        puts "[System Error] Failed in trigger_whisper: #{e.message}"
      end
    end
    
    # ゲーム終了時の反省・感想戦メッセージ送信
    def trigger_reflection_and_epilogue(state_val)
      win_msg = case state_val
                when 2 then "村人の勝利です！"
                when 3 then "人狼の勝利です！"
                else "ゲームが終了しました。"
                end
      
      # 1. 反省と自己学習を実行
      trigger_reflection(win_msg)
      
      # 2. LLM で感想戦メッセージを生成
      puts "\n[Thinking] Drafting epilogue message..."
      system_prompt = "人狼ゲームが決着しました（#{win_msg}）。ゲーム終了後の感想戦（エピローグ）です。あなたのキャラクター「#{@game_state.my_name}」になりきって、ゲームを終えての感想、楽しかった点、他のプレイヤーへの労いの言葉などを1行で発言してください。メタ説明やマークダウン記法、余計な解説は一切含めてはいけません。"
      user_prompt = "ゲームが終了しました。感想戦チャットに最初のメッセージを投稿してください。あなたの役職は #{@game_state.my_role} でした。"
      
      begin
        response = @llm.chat(system_prompt, user_prompt, temperature: 0.8)
        response.gsub!(/^["'「]+/, "")
        response.gsub!(/["'」]+$/, "")
        msg = response.strip
        
        puts "[Action] AI decided to post epilogue message: \"#{msg}\""
        post('cmd' => 'msg', 'message' => msg, 'j_data' => 'a')
        @last_say_time = Time.now
      rescue => e
        puts "[System Error] Failed to generate epilogue greeting: #{e.message}"
      end
    end
    
    # 感想戦中の雑談・対話
    def check_and_say_epilogue
      puts "\n[Thinking] Reacting to epilogue chat..."
      system_prompt = "人狼ゲームが終了した後の感想戦（エピローグ）の雑談です。あなたのキャラクターになりきって、これまでの他のプレイヤーの発言に対して返答、雑談、あるいは軽い感想を1行で発言してください。余計なマークダウンやメタ解説は一切含めてはいけません。"
      user_prompt = "これまでの感想戦チャットログを踏まえて発言してください。\n#{@game_state.formatted_chat_logs}"
      
      begin
        response = @llm.chat(system_prompt, user_prompt, temperature: 0.8)
        response.gsub!(/^["'「]+/, "")
        response.gsub!(/["'」]+$/, "")
        msg = response.strip
        
        puts "[Action] AI decided to post epilogue chat: \"#{msg}\""
        post('cmd' => 'msg', 'message' => msg, 'j_data' => 'a')
        @last_say_time = Time.now
      rescue => e
        puts "[System Error] Failed to generate epilogue chat: #{e.message}"
      end
    end
    
    # 役職から所属陣営を判別
    def camp_from_role
      case @game_state.my_role
      when "人狼", "狂信者", "C国狂人"
        "werewolf"
      else
        "villager"
      end
    end
    
    # ゲーム終了時の反省・自己学習
    def trigger_reflection(win_announcement)
      puts "\n=== [System] Game Finished: Running reflection and learning ==="
      
      won = false
      if win_announcement.include?("村人の勝利") && camp_from_role == "villager"
        won = true
      elsif win_announcement.include?("人狼の勝利") && camp_from_role == "werewolf"
        won = true
      end
      
      all_logs_text = ""
      begin
        (1..@game_state.current_day).each do |day|
          res = get_api('cmd' => 'log', 'date' => day.to_s)
          if res && res.code == '200'
            all_logs_text += "=== #{day}日目のログ ===\n" + res.body + "\n\n"
          end
        end
      rescue => e
        puts "[System Error] Failed to fetch full logs: #{e.message}"
        all_logs_text = @game_state.formatted_chat_logs
      end
      
      success = @learning.run_reflection(@vid, @game_state.my_role, won, all_logs_text)
      if success
        puts "[System] Reflection finished and saved to memory."
      else
        puts "[System] Reflection failed."
      end
    end
  end
end
