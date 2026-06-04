require 'net/http'
require 'uri'
require 'json'
require 'yaml'
require_relative 'game_state'
require_relative 'llm_client'
require_relative 'prompt_manager'
require_relative 'learning_system'

module AnmanAI
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
    end
    
    # 接続・ログイン (Cookieの取得)
    def login!
      uri = URI.parse("#{@url}/aiwolf/index.cgi")
      req = Net::HTTP::Post.new(uri.path)
      req.set_form_data('cmd' => 'login', 'userid' => @userid, 'pass' => @password)
      
      begin
        res = Net::HTTP.start(uri.host, uri.port) { |http| http.request(req) }
        if res.code == '200' || res.code == '302'
          set_cookie_header = res['Set-Cookie']
          if set_cookie_header
            @cookie = set_cookie_header.split(';').first
          end
          puts "[System] Logged in successfully to #{@url} as #{@userid}."
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
        Net::HTTP.start(uri.host, uri.port) { |http| http.request(req) }
      rescue => e
        puts "[System] Error posting action #{params['cmd']}: #{e.message}"
      end
    end
    
    # GET送信ヘルパー
    def get_api(params)
      uri = URI.parse("#{@url}/aiwolf/api.cgi")
      uri.query = URI.encode_www_form(params.merge('vid' => @vid.to_s))
      req = Net::HTTP::Get.new(uri)
      req['Cookie'] = @cookie if @cookie
      
      begin
        res = Net::HTTP.start(uri.host, uri.port) { |http| http.request(req) }
        res.body.force_encoding('UTF-8') if res && res.body
        res
      rescue => e
        puts "[System] Error fetching API #{params['cmd']}: #{e.message}"
        nil
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
      since_id = 0
      
      loop do
        begin
          res = get_api('cmd' => 'events', 'since' => since_id.to_s)
          puts "[DEBUG] get_api(events, since: #{since_id}) code: #{res ? res.code : 'nil'}"
          if res && res.code == '200'
            events = JSON.parse(res.body)
            puts "[DEBUG] Received #{events.size} events"
            events.each do |e|
              puts "[DEBUG] Event: ID=#{e['id']}, type=#{e['type']}, type_code=#{e['type_code']}"
              @game_state.process_event(e)
              since_id = [since_id, e['id'].to_i].max
              
              # イベントごとのアクションハンドリング
              handle_event_action(e)
            end
            
            # イベントがあった場合のみ発言判定を行う
            if !events.empty?
              puts "[DEBUG] Triggering check_and_say"
              check_and_say
            end
          end
        rescue Interrupt
          puts "[System] Interrupt received. Stopping client..."
          break
        rescue => e
          puts "[System] Error in main loop: #{e.class} - #{e.message}"
          sleep 5 # エラー時のスリープ
        end
      end
    end
    
    # イベントに応じた自動アクションのトリガー
    def handle_event_action(e)
      # 1. 投票フェーズへの移行検知
      if e['type'] == 'system' && e['type_code'] == 'announce' && e['content'].include?("投票を行うことにしました")
        trigger_vote
      end
      
      # 2. 夜フェーズへの移行検知
      if e['type'] == 'state_change' && e['type_code'] == 'time' && e['content'].include?("夜になりました")
        trigger_night_action
      end
      
      # 3. 勝敗決定（ゲーム終了）の検知
      if e['type'] == 'system' && e['type_code'] == 'announce' && e['content'].include?("の勝利です！")
        trigger_reflection(e['content'])
      end
    end
    
    # 昼の発言処理
    def check_and_say
      puts "[DEBUG] check_and_say - is_night: #{@game_state.is_night}, day: #{@game_state.current_day}"
      return if @game_state.is_night
      return if @game_state.current_day < 1
      
      # 発言頻度コントロール (10秒に1回以上は発言しない)
      time_diff = Time.now - @last_say_time
      puts "[DEBUG] Time since last say: #{time_diff}s"
      return if time_diff < 10
      
      puts "\n[Thinking] Evaluating chat response (using LLM: #{@llm.model})..."
      
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
      
      system_prompt = "あなたは人狼ゲームのプレイヤーです。必ず指定されたJSONフォーマットで回答してください。JSON以外の文章は一切含めてはいけません。"
      user_prompt = @prompts.build_prompt('say', vars)
      
      begin
        response = @llm.chat(system_prompt, user_prompt)
        clean_res = response.gsub(/^```json\s*/, "").gsub(/```\s*$/, "").strip
        parsed = JSON.parse(clean_res)
        
        # 推理メモの引き継ぎ更新
        if parsed['reasoning_update'] && !parsed['reasoning_update'].empty?
          @game_state.my_reasoning_notes = parsed['reasoning_update']
        end
        
        # 発言の実行
        msg = parsed['message']
        if msg && !msg.empty?
          puts "[Action] AI decided to say: \"#{msg}\""
          post('cmd' => 'msg', 'message' => msg, 'j_data' => 'あ')
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
          # 生存している自分以外のプレイヤーにランダム投票
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
      
      # 人狼の夜会話（ささやき）
      if @game_state.my_role == "人狼" && !@whispered_tonight[day]
        trigger_whisper
      end
      
      # 占い能力の行使
      return if @acted_tonight[day]
      return unless @game_state.my_role == "占い師"
      
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
          # フォールバック（まだ占っていない生存プレイヤーへランダム占い）
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
          post('cmd' => 'msg', 'message' => msg, 'whisper' => 'on', 'j_data' => 'あ')
        end
        @whispered_tonight[day] = true
      rescue => e
        puts "[System Error] Failed in trigger_whisper: #{e.message}"
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
      
      # 勝敗判定
      won = false
      if win_announcement.include?("村人の勝利") && camp_from_role == "villager"
        won = true
      elsif win_announcement.include?("人狼の勝利") && camp_from_role == "werewolf"
        won = true
      end
      
      # API経由で終了した村の全ログを日付順に回収
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
      
      # 反省を実行して記録
      success = @learning.run_reflection(@vid, @game_state.my_role, won, all_logs_text)
      if success
        puts "[System] Reflection finished and saved to memory."
      else
        puts "[System] Reflection failed."
      end
    end
  end
end
