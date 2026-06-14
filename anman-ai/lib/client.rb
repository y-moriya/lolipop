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
    attr_reader :config_path, :exe_dir, :internal_root_dir, :game_state, :my_name, :my_role, :vid, :userid, :url, :running

    def self.load_config(config_path)
      begin
        config = YAML.load_file(config_path)
        config = {} unless config.is_a?(Hash)
      rescue => e
        puts "[Fatal Error] Failed to parse config file at #{config_path}: #{e.message}"
        config = {}
      end

      if config['llm_config']
        config_dir = File.dirname(config_path)
        llm_config_path = File.expand_path(config['llm_config'], config_dir)
        if File.exist?(llm_config_path)
          begin
            llm_config = YAML.load_file(llm_config_path)
            llm_config = {} unless llm_config.is_a?(Hash)
            config['llm'] = llm_config['llm'] if llm_config['llm']
            config['llm_fallback'] = llm_config['llm_fallback'] if llm_config['llm_fallback']
          rescue => e
            puts "[System WARNING] Failed to parse LLM config at #{llm_config_path}: #{e.message}"
          end
        else
          puts "[System WARNING] Referenced LLM config file not found: #{llm_config_path}"
        end
      end
      config
    end

    def initialize(config_path, exe_dir, internal_root_dir = nil)
      @config_path = config_path
      @exe_dir = exe_dir
      @internal_root_dir = internal_root_dir || exe_dir
      @config = Client.load_config(config_path)
      @running = false
      
      server_config = @config['server'] || {}
      @url = server_config['url']
      if @url
        @url = @url.sub(/\/aiwolf\/?\z/, '').chomp('/')
      end
      @vid = server_config['vid']
      
      user_config = @config['user'] || {}
      @userid = user_config['userid']
      @password = user_config['password']
      
      @cookie = nil
      @game_state = GameState.new(@userid)
      @llm = LLMClient.new(@config)
      @prompts = PromptManager.new(exe_dir, @internal_root_dir)
      @learning = LearningSystem.new(exe_dir, @llm)

      # コンパクトプロンプトモード: サマリー＋差分ログのみLLMに渡す（長大プロンプト防止）
      @compact_prompt = @config.dig('llm', 'compact_prompt') != false
      puts "[System] Compact prompt mode: #{@compact_prompt ? 'ON（サマリー+差分ログ）' : 'OFF（全ログ）'}"

      # 発言頻度の制限設定（設定がない場合はデフォルト値を使用）
      @talk_interval_reactive = @config.dig('llm', 'talk_interval_reactive') || 10
      @talk_interval_active = @config.dig('llm', 'talk_interval_active') || 60
      @auto_adjust_talk_interval = @config.dig('llm', 'auto_adjust_talk_interval') != false
      @budget_mode = @config.dig('llm', 'budget_mode') || 'normal'
      @current_talk_interval_reactive = @talk_interval_reactive
      @current_talk_interval_active = @talk_interval_active
      puts "[System] Talk intervals - Reactive: #{@talk_interval_reactive}s, Active: #{@talk_interval_active}s, AutoAdjust: #{@auto_adjust_talk_interval}, BudgetMode: #{@budget_mode}"

      @voted_today = {}       # { day => bool }
      @acted_tonight = {}     # { day => bool }
      @whispered_tonight = {} # { day => bool }
      @last_say_time = Time.at(0)
      @last_chat_logs_size = 0

      @reflected_and_greeting = false
      @epilogue_start_time = nil

      # アンカー解決機能: true の場合、ログ内の >>N を対応発言内容に展開してLLMに渡す
      @anchor_resolution = @config.dig('llm', 'anchor_resolution') != false
      puts "[System] Anchor resolution: #{@anchor_resolution ? 'ON（>>Nを発言内容に展開）' : 'OFF（原文のまま）'}"
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
    
    # 既に参加済みの進行中・募集中の村を探し、あればその vid をセットして true を返す
    # 存在しなければ false を返す
    def find_active_joined_village
      res = get_api('cmd' => 'vils')
      return false unless res && res.code == '200'
      vils = JSON.parse(res.body)
      # 自分が参加済みの村（state=0:募集中 / state=1:進行中）を探す
      active = vils.find do |v|
        v['state'].to_i <= 1 && v['joined'] == true
      end
      if active
        @vid = active['vid'].to_i
        puts "[System] Found already-joined village: vid=#{@vid} (#{active['name']}, state=#{active['state']})"
        return true
      end
      false
    rescue => e
      puts "[System Error] find_active_joined_village failed: #{e.message}"
      false
    end

    # 募集中の村を監視し、自動でエントリーする
    def auto_entry_loop!
      puts "[System] Scoping recruiting villages..."
      while @running
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
      system_prompt = "あなたは人狼ゲームのキャラクター「#{char_name}」です。そのキャラクターになりきって、入村時の挨拶メッセージを1行で作成してください。発言の冒頭に「#{char_name}:」などの名前を含めないでください。発言本文のみを出力してください。まだ村が開始される前のエントリー段階ですので、誰が何の役職になるかは分かりません。そのため、役職に関する言及やゲームの議論・推理などは一切含めず、純粋な挨拶と自己紹介のみを行ってください。挨拶以外のメタ発言や余計な解説、マークダウン記法（ダブルクォーテーションや```等）は一切含めてはいけません。"
      user_prompt = "人狼ゲームの村のエントリー（点呼）に参加しました。他のプレイヤーたちに、自己紹介を兼ねて入村の挨拶をしてください。"
      
      begin
        @last_say_time = Time.now
        response = @llm.chat(system_prompt, user_prompt, temperature: 0.8)
        clean_llm_message(response, char_name)
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

      # 村の状態を取得して日付を同期
      res_vil = get_api('cmd' => 'vil')
      if res_vil && res_vil.code == '200'
        vil_info = JSON.parse(res_vil.body)
        @game_state.current_day = vil_info['date'].to_i
        @game_state.is_night = vil_info['night']
        if vil_info['state'].to_i >= 1
          @game_state.game_started = true
        end
      end
      
      # 初回の状態同期を実行
      sync_game_status_from_server!
    end

    # ゲーム開始時に自分の役職をサーバーから再取得して同期する
    def check_and_update_role_if_started!(game_state_val)
      if game_state_val >= 1 && (!@game_state.game_started || @game_state.my_role == "未決定" || @game_state.my_role == "不明")
        @game_state.game_started = true
        res_players = get_api('cmd' => 'players')
        if res_players && res_players.code == '200'
          players_json = JSON.parse(res_players.body)
          current_player = players_json.find { |p| p['userid'] == @userid }
          @game_state.init_players(players_json, current_player)
          puts "[System] Game started! Your assigned role is: #{@game_state.my_role}."
        end
      end
    end

    # サーバーから投票や夜アクション、ささやき等の実行状態を同期し、
    # クライアント再起動時や状態変化時に重複して行動を起こさないようにする
    def sync_game_status_from_server!
      day = @game_state.current_day
      
      # 1. 投票と夜アクションの状態同期
      res_players = get_api('cmd' => 'players')
      if res_players && res_players.code == '200'
        players_json = JSON.parse(res_players.body)
        me = players_json.find { |p| p['userid'] == @userid }
        @game_state.init_players(players_json, me)
        if me
          if me['voted'] == true
            unless @voted_today[day]
              @voted_today[day] = true
              puts "[System] Synchronized status: Already voted today (Day #{day})."
            end
          end
          if me['acted'] == true
            unless @acted_tonight[day]
              @acted_tonight[day] = true
              puts "[System] Synchronized status: Already acted tonight (Day #{day})."
            end
          end
        end
      end
      
      # 2. 人狼ささやきの状態同期（過去のチャットログに自身のささやきがあるか）
      if @game_state.my_role == "人狼" && !@whispered_tonight[day]
        has_whispered = @game_state.chat_logs.any? do |log|
          log['day'].to_i == day &&
            (log['type_code'] == 'whisper' || log['type_code'] == 'whisperhowl') &&
            log['speaker'] == @game_state.my_name
        end
        if has_whispered
          @whispered_tonight[day] = true
          puts "[System] Synchronized status: Already whispered tonight (Day #{day})."
        end
      end
    end
    
    # メインループ
    def start_loop!
      puts "[System] Starting event monitoring loop..."
      events_queue = Queue.new
      since_id = 0
      
      # 1. バックグラウンドでイベントをロングポーリング受信するスレッド
      event_thread = Thread.new do
        while @running
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
      
      is_catching_up = true
      
      while @running
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
          
          if is_catching_up
            is_catching_up = false
            # 同期する前に、1回限りの vil 情報取得を行って現在の日付/夜昼を合わせる
            res_vil = get_api('cmd' => 'vil')
            if res_vil && res_vil.code == '200'
              vil_info = JSON.parse(res_vil.body)
              update_time = vil_info['update_time'].to_i
              game_state_val = vil_info['state'].to_i
              @game_state.current_day = vil_info['date'].to_i
              @game_state.is_night = vil_info['night']
              @game_state.game_started = true if game_state_val >= 1
              check_and_update_role_if_started!(game_state_val)
              adjust_talk_intervals!(vil_info['period'].to_i)
            end

            # サーバーから状態を同期
            sync_game_status_from_server!

            @last_chat_logs_size = @game_state.chat_logs.size
            @last_say_time = Time.now
            puts "[System] Catchup completed. Synchronized chat logs size: #{@last_chat_logs_size}."
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

              # 村のステータスが進行中(1)以上であればゲーム開始済みとみなす
              if game_state_val >= 1
                @game_state.game_started = true
              end

              check_and_update_role_if_started!(game_state_val)
              adjust_talk_intervals!(vil_info['period'].to_i)

              # 進行中または募集中の場合は状態同期を実行
              if game_state_val <= 1
                sync_game_status_from_server!
              end
            end
            last_vil_check = Time.now
          end
          
          # ゲームが終了（決着）した場合は感想戦モードに入る
          if game_state_val >= 2
            unless @reflected_and_greeting
              puts "[System] Game is over. Running reflection and posting epilogue chat..."
              # 勝敗メッセージをインスタンス変数に保存（check_and_say_epilogue でも参照）
              @epilogue_win_msg = case game_state_val
                                  when 2 then "村人の勝利です！"
                                  when 3 then "人狼の勝利です！"
                                  else "ゲームが終了しました。"
                                  end
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
            
            # 感想戦中は、他の参加者からの新着メッセージがあった場合のみ反応して発言する（一人の連投を防ぐ）
            time_since_last_say = Time.now - @last_say_time
            current_chat_size = @game_state.chat_logs.size
            if current_chat_size > @last_chat_logs_size
              new_logs = @game_state.chat_logs[@last_chat_logs_size..-1] || []
              is_others_msg = new_logs.any? do |log|
                !log['is_mine'] && log['speaker'] != @game_state.my_name && log['type_code'] == 'say'
              end
              
              if is_others_msg
                if time_since_last_say >= 10
                  check_and_say_epilogue
                  @last_chat_logs_size = current_chat_size
                end
              else
                @last_chat_logs_size = current_chat_size
              end
            end
            
            sleep 1
            next
          end
          
          # ゲーム開始前（募集中・点挙中）の雑談
          if game_state_val == 0 && @game_state.my_name
            time_since_last_say = Time.now - @last_say_time
            current_chat_size = @game_state.chat_logs.size
            if current_chat_size > @last_chat_logs_size
              new_logs = @game_state.chat_logs[@last_chat_logs_size..-1] || []
              is_others_msg = new_logs.any? do |log|
                !log['is_mine'] && log['speaker'] != @game_state.my_name && log['type_code'] == 'say'
              end
              
              if is_others_msg
                if time_since_last_say >= 10
                  check_and_say_recruiting
                  @last_chat_logs_size = current_chat_size
                end
              else
                @last_chat_logs_size = current_chat_size
              end
            end
            sleep 1
            next
          end
          
          # ゲームが開始されるまでは、以降の自律アクション（発言・投票・夜行動など）は行わない
          next unless @game_state.game_started

          # 昼夜の状態に応じた自律アクション判断
          day = @game_state.current_day
          remain_sec = update_time - Time.now.to_i
          
          # 自分が死亡しているか確認
          my_player = @game_state.players[@game_state.my_name]
          is_dead = my_player && my_player[:dead] != 0
          
          # 1. 自律的・反応的な発言・思考発信の判定 (昼夜、生存死亡を問わず実行)
          time_since_last_say = Time.now - @last_say_time
          current_chat_size = @game_state.chat_logs.size
          
          if current_chat_size > @last_chat_logs_size
            new_logs = @game_state.chat_logs[@last_chat_logs_size..-1] || []
            others_spoke = new_logs.any? do |log|
              !log['is_mine'] && 
                log['speaker'] != @game_state.my_name && 
                ['say', 'think', 'whisper', 'groan', 'whisperhowl'].include?(log['type_code'])
            end
            
            # 発言がなかった（システムログや自分の発言のみ）の場合はここで index を進める
            unless others_spoke
              @last_chat_logs_size = current_chat_size
            end
          else
            others_spoke = false
          end

          # 反応発言は前回の発言から指定された秒数以上空いていれば実行（デフォルトは10秒、時間自動伸縮あり）
          # 能動的発言は指定された秒数以上空いていれば実行（デフォルトは60秒、時間自動伸縮あり）
          if (others_spoke && time_since_last_say >= @current_talk_interval_reactive) || (time_since_last_say >= @current_talk_interval_active)
            check_and_say
            @last_chat_logs_size = current_chat_size
          end
          
          if @game_state.is_night
            puts "[DEBUG client.rb] is_night=true, role=#{@game_state.my_role}, acted=#{@acted_tonight[day]}, dead=#{is_dead}"
            # 夜フェーズ (生存時のみアクション可能)
            unless is_dead
              # 1. 人狼のささやき（夜の初めに1回）
              if @game_state.my_role == "人狼" && !@whispered_tonight[day]
                trigger_whisper
              end
              
              # 2. 夜アクションの実行（占い、人狼襲撃、護衛など）
              if role_has_night_action?
                if !@acted_tonight[day]
                  trigger_night_action
                end
              else
                @acted_tonight[day] = true
              end
            end
          else
            # 昼フェーズ
            # 更新時間が近づいたら投票を行う (テストモード、または残り時間45秒以下、かつ未投票、生存時のみ)
            unless is_dead
              is_test_mode = ENV['ANMAN_TEST_MODE'] == 'true' || ENV['ANMAN_QUICK_VOTE'] == 'true'
              if !@voted_today[day] && remain_sec > 0 && (remain_sec <= 45 || is_test_mode)
                # Sync vote status from server first
                res_players = get_api('cmd' => 'players')
                if res_players && res_players.code == '200'
                  players_json = JSON.parse(res_players.body)
                  me = players_json.find { |p| p['userid'] == @userid }
                  if me && me['voted'] == true
                    @voted_today[day] = true
                    puts "[System] Synchronized vote status: already voted today."
                  end
                end

                if !@voted_today[day]
                  if remain_sec <= 7
                    puts "[System WARNING] Very close to voting deadline (#{remain_sec}s remaining). Skipping LLM and executing quick fallback vote."
                    trigger_quick_fallback_vote!
                  else
                    puts "[System] Deadline approaching (#{remain_sec}s remaining). Triggering vote."
                    trigger_vote
                  end
                end
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
    
    # コンパクトモード切り替え: chat_logsに渡す内容を決定するヘルパー
    # compact_prompt=true  → 「ゲームサマリー + 新着差分ログのみ」を返す
    # compact_prompt=false → 「全チャットログ」を返す
    # anchor_resolution=true の場合、チャットログ内の >>N を対応発言内容に展開する
    def build_log_context
      if @compact_prompt
        summary = @game_state.game_summary
        incremental = @game_state.incremental_chat_logs(resolve_anchor: @anchor_resolution)
        "#{summary}\n\n【新着チャット（前回送信以降）】\n#{incremental}"
      else
        @game_state.formatted_chat_logs(resolve_anchor: @anchor_resolution)
      end
    end

    # LLMが anchor_request: N を返したとき、N番のアンカーを解決して追加コンテキストを返す
    # 解決できた場合: "【アンカー参照結果】>>N: 発言者「内容」" を返す
    # 解決できなかった場合: nil を返す
    def resolve_anchor_request(anchor_num)
      return nil unless anchor_num.is_a?(Integer) && anchor_num > 0
      day = @game_state.current_day
      resolved = @game_state.resolve_anchors(">>#{anchor_num}", day)
      # 解決できなかった場合は原文のまま返ってくる
      if resolved == ">>#{anchor_num}"
        puts "[Anchor] >>#{anchor_num} could not be resolved (not found in say_index)"
        nil
      else
        puts "[Anchor] Resolved >>#{anchor_num}: #{resolved}"
        "【アンカー参照結果】LLMが >>#{anchor_num} の内容を要求しました。該当発言: #{resolved}"
      end
    end

    # LLMレスポンスをJSONとしてパースするヘルパー
    # JSONが完全な場合は通常パース、途中切れの場合はregexでフィールドを個別抽出する
    def parse_llm_json(raw_response)
      # Markdownコードブロック除去
      clean = raw_response.gsub(/\A```json\s*/m, "").gsub(/\A```\s*/m, "").gsub(/```\s*\z/m, "").strip

      # 通常パースを試みる
      begin
        return JSON.parse(clean)
      rescue JSON::ParserError
        # フォールバック: 各フィールドをregexで個別抽出
        STDERR.puts "[LLM Warning] JSON incomplete, attempting field extraction..."
        result = {}

        # message フィールド抽出
        if clean =~ /"message"\s*:\s*"((?:[^"\\]|\\.)*)"/m
          result['message'] = $1.gsub(/\\"/, '"').gsub(/\\n/, "\n")
        end
        # vote_target フィールド抽出
        if clean =~ /"vote_target"\s*:\s*"((?:[^"\\]|\\.)*)"/m
          result['vote_target'] = $1
        end
        # fortune_target フィールド抽出
        if clean =~ /"fortune_target"\s*:\s*"((?:[^"\\]|\\.)*)"/m
          result['fortune_target'] = $1
        end
        # reasoning_update フィールド抽出
        if clean =~ /"reasoning_update"\s*:\s*"((?:[^"\\]|\\.)*)"/m
          result['reasoning_update'] = $1.gsub(/\\"/, '"')
        end
        # thought フィールド抽出（任意）
        if clean =~ /"thought"\s*:\s*"((?:[^"\\]|\\.)*)"/m
          result['thought'] = $1
        end
        # anchor_request フィールド抽出（整数または null）
        if clean =~ /"anchor_request"\s*:\s*(\d+)/
          result['anchor_request'] = $1.to_i
        end

        # 何も抽出できなければ例外を再発生
        raise JSON::ParserError, "Could not extract any fields from LLM response" if result.empty?
        result
      end
    end

    # LLMの応答テキストから、不要なクォーテーション、括弧、名前プレフィックスを取り除く
    def clean_llm_message(text, name = nil)
      return "" unless text
      cleaned = text.strip
      
      # 1. 括弧や引用符で全体が囲まれている場合はペアで剥ぎ取る
      while cleaned =~ /\A(["'「『])(.*)(["'」』])\z/m
        cleaned = $2.strip
      end
      
      # 2. 名前プレフィックス（例：「学士 ノエル: 」など）をトリムする
      if name
        name_no_space = name.gsub(/\s+/, '')
        # 「学士 ノエル」のようにスペースが含まれる場合のパターン
        # コロンは半角・全角の両方に対応
        pat = /^(?:#{Regexp.escape(name)}|#{Regexp.escape(name_no_space)})\s*[:：]\s*/i
        cleaned.sub!(pat, '')
      end
      
      # 3. 再度、全体を囲む括弧などがあれば削る（「学士 ノエル: 楽しかった」 -> 「楽しかった」 対策）
      while cleaned =~ /\A(["'「『])(.*)(["'」』])\z/m
        cleaned = $2.strip
      end
      
      # 4. 残った先頭・末尾 of ゴミ記号を個別に除去する
      cleaned.gsub!(/\A["'「『]+/, "")
      cleaned.gsub!(/["'」』]+\z/, "")
      
      # 5. もう一度名前プレフィックス除去（念のため）
      if name
        name_no_space = name.gsub(/\s+/, '')
        pat = /^(?:#{Regexp.escape(name)}|#{Regexp.escape(name_no_space)})\s*[:：]\s*/i
        cleaned.sub!(pat, '')
      end
      
      cleaned.strip
    end

    # 自律的・反応的な発言・思考発信処理（生存/死亡、昼/夜に応じてメッセージ種別を切り替える）
    def check_and_say
      return unless @game_state.game_started
      
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
        'current_day'      => @game_state.current_day,
        'my_name'          => @game_state.my_name,
        'my_role'          => @game_state.my_role,
        'surviving_players'=> @game_state.surviving_players_list,
        'dead_players'     => @game_state.dead_players_list,
        'my_reasoning_notes' => @game_state.my_reasoning_notes,
        'my_recent_says'   => @game_state.my_recent_says,
        'chat_logs'        => build_log_context,
        'learning_memory'  => @learning.load_memory_text,
        'role_instructions'=> @prompts.load_camp_prompt(camp_from_role)
      }
      
      # 前回の発言から28秒以上経過している場合は、能動的発信（沈黙タイムアウト）とみなす
      time_since_last_say = Time.now - @last_say_time
      is_test = @url.include?("localhost") || @url.include?("127.0.0.1")
      active_threshold = is_test ? 3 : 28
      is_active_trigger = (time_since_last_say >= active_threshold)
      
      system_prompt = "あなたは人狼ゲームのプレイヤー「#{@game_state.my_name}」です。必ず指定されたJSONフォーマットで回答してください。JSON以外の文章は一切含めてはいけません。\n" \
                      "【超重要・発言文字数の制限】会話に馴染むため、message に入れる発言は「30〜80文字以内（最大でも2文）」にしてください。絶対に長文を書いてはいけません。\n" \
                      "【超重要・NGワード】「データ、エミュレーション、システム、共通認識、論理的、変数、感情論、前提、整合性、分析、パラメータ、定量化」といった冷たい論文調・機械的・メタ的な言葉は絶対に使わないでください。普通の人間として日常会話風に短く推理や雑談をしてください。"
      
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
        puts "[System DEBUG] LLM raw response: #{response.inspect}"
        parsed = parse_llm_json(response)

        # anchor_request: N が返ってきた場合、アンカーを解決して1度だけ再問い合わせ
        if parsed['anchor_request'] && !parsed['anchor_request'].to_s.empty? && parsed['anchor_request'].to_i > 0
          anchor_context = resolve_anchor_request(parsed['anchor_request'].to_i)
          if anchor_context
            puts "[Anchor] Re-querying LLM with anchor context for >>#{parsed['anchor_request']}"
            retry_prompt = user_prompt + "\n\n#{anchor_context}\n\n上記のアンカー参照内容を踏まえて、改めて発言を決定してください。"
            response = @llm.chat(system_prompt, retry_prompt)
            parsed = parse_llm_json(response)
          end
        end

        if parsed['reasoning_update'] && !parsed['reasoning_update'].empty?
          @game_state.my_reasoning_notes = parsed['reasoning_update']
        end
        
        msg = parsed['message']
        msg = clean_llm_message(msg, @game_state.my_name) if msg
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
        @game_state.mark_logs_sent!
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
        'current_day'       => day,
        'my_name'           => @game_state.my_name,
        'my_role'           => @game_state.my_role,
        'surviving_players' => @game_state.surviving_players_list,
        'my_reasoning_notes'=> @game_state.my_reasoning_notes,
        'chat_logs'         => build_log_context,
        'learning_memory'   => @learning.load_memory_text,
        'role_instructions' => @prompts.load_camp_prompt(camp_from_role)
      }
      
      system_prompt = "あなたは人狼ゲームのプレイヤーです。必ず指定されたJSONフォーマットで回答してください。JSON以外の文章は一切含めてはいけません。"
      user_prompt = @prompts.build_prompt('vote', vars)
      
      begin
        response = @llm.chat(system_prompt, user_prompt, temperature: 0.2)
        parsed = parse_llm_json(response)
        
        target_name = parsed['vote_target']
        target_player = @game_state.players[target_name]
        
        if target_player && target_player[:dead] == 0 && target_name != @game_state.my_name
          puts "[Action] AI decided to vote for: #{target_name} (ID: #{target_player[:num_id]})"
          post(
            'cmd' => 'vote', 
            'vote_id' => target_player[:num_id].to_s, 
            'set_date' => day.to_s
          )
          @voted_today[day] = true
          @game_state.mark_logs_sent!
        else
          puts "[Action] AI target name '#{target_name}' is invalid or dead. Fallback to quick voting."
          trigger_quick_fallback_vote!
        end
      rescue => e
        puts "[System Error] Failed in trigger_vote: #{e.message}. Running quick fallback."
        trigger_quick_fallback_vote!
      end
    end

    def trigger_quick_fallback_vote!
      day = @game_state.current_day
      return if @voted_today[day]
      
      fallback_target = @game_state.players.select { |name, p| p[:dead] == 0 && name != @game_state.my_name }.values.sample
      if fallback_target
        puts "[Action] Fallback voting for: #{fallback_target[:name]} (ID: #{fallback_target[:num_id]})"
        post(
          'cmd' => 'vote', 
          'vote_id' => fallback_target[:num_id].to_s, 
          'set_date' => day.to_s
        )
        @voted_today[day] = true
        @game_state.mark_logs_sent!
      end
    end

    # 夜アクション（占い・護衛・人狼ささやきなど）の実行
    def trigger_night_action
      day = @game_state.current_day
      role = @game_state.my_role
      
      # Determine action parameters based on role
      action_name = nil
      target_key = nil
      role_label = nil
      verb = nil
      
      case role
      when "占い師", "中身占い師"
        action_name = "fortune"
        target_key = "fortune_target"
        role_label = "占い師"
        verb = "占い"
      when "人狼", "絶対人狼"
        action_name = "attack"
        target_key = "attack_target"
        role_label = "人狼"
        verb = "襲撃"
      when "狩人", "風来狩人"
        action_name = "guard"
        target_key = "guard_target"
        role_label = "狩人"
        verb = "護衛"
      when "求愛者"
        action_name = "woo"
        target_key = "woo_target"
        role_label = "求愛者"
        verb = "求愛"
      when "邪魔狂人"
        action_name = "jam"
        target_key = "jam_target"
        role_label = "邪魔狂人"
        verb = "邪魔"
      when "キューピッド"
        trigger_cupid_action
        return
      else
        @acted_tonight[day] = true
        return
      end
      
      puts "\n[Thinking] Deciding who to #{verb} tonight..."
      
      vars = {
        'current_day'        => day,
        'my_name'            => @game_state.my_name,
        'my_role'            => role,
        'surviving_players'  => @game_state.surviving_players_list,
        'action_results'     => @game_state.formatted_action_results,
        'my_reasoning_notes' => @game_state.my_reasoning_notes,
        'chat_logs'          => build_log_context,
        'learning_memory'    => @learning.load_memory_text,
        'role_instructions'  => @prompts.load_camp_prompt(camp_from_role)
      }
      
      system_prompt = "あなたは人狼ゲームの#{role_label}です。必ず指定されたJSONフォーマットで回答してください。JSON以外の文章は一切含めてはいけません。"
      
      # Build the prompt by taking fortune.txt and replacing templates
      user_prompt = @prompts.build_prompt('fortune', vars)
      if action_name != "fortune"
        user_prompt = user_prompt
          .gsub("占い師", role_label)
          .gsub("正体を占う", "正体を#{verb}する")
          .gsub("占い対象", "#{verb}対象")
          .gsub("fortune_target", target_key)
      end
      
      begin
        response = @llm.chat(system_prompt, user_prompt, temperature: 0.2)
        parsed = parse_llm_json(response)
        
        target_name = parsed[target_key] || parsed['fortune_target']
        target_player = @game_state.players[target_name]
        
        # Validation: target must be alive and not myself (and not partners if werewolf)
        is_valid = target_player && target_player[:dead] == 0 && target_name != @game_state.my_name
        if role.include?("人狼") && target_name && @game_state.werewolf_partners.include?(target_name)
          is_valid = false # Don't attack partners
        end
        
        if is_valid
          puts "[Action] AI decided to #{verb}: #{target_name} (ID: #{target_player[:num_id]})"
          post(
            'cmd' => 'skill',
            'target_id' => target_player[:num_id].to_s,
            'set_date' => day.to_s
          )
          @acted_tonight[day] = true
          @game_state.action_results << "#{day}日目夜: #{target_name} を#{verb}対象としてセットしました。"
          @game_state.mark_logs_sent!
        else
          puts "[System Warning] LLM returned invalid target '#{target_name}'. Running fallback."
          trigger_quick_fallback_night_action!
        end
      rescue => e
        puts "[System Error] Failed in trigger_night_action: #{e.message}. Running fallback."
        trigger_quick_fallback_night_action!
      end
    end

    def trigger_quick_fallback_night_action!
      day = @game_state.current_day
      return if @acted_tonight[day]

      targets = @game_state.players.select { |name, p| p[:dead] == 0 && name != @game_state.my_name }
      if @game_state.my_role.include?("人狼")
        # 人狼は仲間の人狼以外を襲撃する
        targets = targets.select { |name, p| !@game_state.werewolf_partners.include?(name) }
      end

      fallback_target = targets.values.sample || @game_state.players.select { |name, p| p[:dead] == 0 && name != @game_state.my_name }.values.sample
      if fallback_target
        puts "[Action] Quick fallback night action target selected: #{fallback_target[:name]} (ID: #{fallback_target[:num_id]})"
        post(
          'cmd' => 'skill',
          'target_id' => fallback_target[:num_id].to_s,
          'set_date' => day.to_s
        )
        @acted_tonight[day] = true
      end
    end

    def trigger_cupid_action
      day = @game_state.current_day
      return if @acted_tonight[day]
      
      # Cupid selects 2 different surviving players (excluding itself)
      others = @game_state.players.select { |name, p| p[:dead] == 0 && name != @game_state.my_name }.values
      if others.size >= 2
        targets = others.sample(2)
        puts "[Action] Cupid selecting: #{targets[0][:name]} and #{targets[1][:name]}"
        post(
          'cmd' => 'skill',
          'target_id' => targets[0][:num_id].to_s,
          'target_id2' => targets[1][:num_id].to_s,
          'set_date' => day.to_s
        )
      elsif others.size == 1
        puts "[Action] Cupid selecting single target: #{others[0][:name]}"
        post(
          'cmd' => 'skill',
          'target_id' => others[0][:num_id].to_s,
          'target_id2' => "-1",
          'set_date' => day.to_s
        )
      end
      @acted_tonight[day] = true
    end

    def role_has_night_action?
      ["占い師", "中身占い師", "人狼", "絶対人狼", "狩人", "風来狩人", "求愛者", "邪魔狂人", "キューピッド"].include?(@game_state.my_role)
    end
    
    # 人狼のささやきの実行
    def trigger_whisper
      day = @game_state.current_day
      puts "\n[Thinking] Drafting werewolf whisper chat..."
      
      vars = {
        'current_day'        => day,
        'my_name'            => @game_state.my_name,
        'surviving_players'  => @game_state.surviving_players_list,
        'werewolf_partners'  => @game_state.werewolf_partners.join(", "),
        'my_reasoning_notes' => @game_state.my_reasoning_notes,
        'chat_logs'          => build_log_context,
        'learning_memory'    => @learning.load_memory_text,
        'role_instructions'  => @prompts.load_camp_prompt('werewolf')
      }
      
      system_prompt = "あなたは人狼です。必ず指定されたJSONフォーマットで回答してください。JSON以外の文章は一切含めてはいけません。"
      user_prompt = @prompts.build_prompt('whisper', vars)
      
      begin
        response = @llm.chat(system_prompt, user_prompt)
        parsed = parse_llm_json(response)

        # anchor_request: N が返ってきた場合、アンカーを解決して1度だけ再問い合わせ
        if parsed['anchor_request'] && !parsed['anchor_request'].to_s.empty? && parsed['anchor_request'].to_i > 0
          anchor_context = resolve_anchor_request(parsed['anchor_request'].to_i)
          if anchor_context
            puts "[Anchor] Re-querying whisper LLM with anchor context for >>#{parsed['anchor_request']}"
            retry_prompt = user_prompt + "\n\n#{anchor_context}\n\n上記のアンカー参照内容を踏まえて、改めてささやきを決定してください。"
            response = @llm.chat(system_prompt, retry_prompt)
            parsed = parse_llm_json(response)
          end
        end

        if parsed['reasoning_update'] && !parsed['reasoning_update'].empty?
          @game_state.my_reasoning_notes = parsed['reasoning_update']
        end
        
        msg = parsed['message']
        msg = clean_llm_message(msg, @game_state.my_name) if msg
        if msg && !msg.empty?
          puts "[Action] AI decided to whisper: \"#{msg}\""
          post('cmd' => 'msg', 'message' => msg, 'whisper' => 'on', 'j_data' => 'a')
        end
        @whispered_tonight[day] = true
        @game_state.mark_logs_sent!
      rescue => e
        puts "[System Error] Failed in trigger_whisper: #{e.message}"
      end
    end
    
    # エピローグ用: 全員の配役リストと勝敗を文字列化するヘルパー
    def build_epilogue_context(win_msg)
      lines = []
      lines << "【ゲーム結果】#{win_msg}"
      lines << "【あなたの役職】#{@game_state.my_role}"
      lines << "【あなたが勝ったか】#{camp_from_role == 'villager' ? win_msg.include?('村人') : win_msg.include?('人狼') ? '勝利' : '敗北'}"
      lines << "【全員の配役（ゲーム終了後公開）】"
      # API から最新のプレイヤー情報（役職付き）を取得
      begin
        res = get_api('cmd' => 'players')
        if res && res.code == '200'
          players_json = JSON.parse(res.body)
          players_json.each do |p|
            role = p['role'] || '不明'
            dead_str = p['dead'].to_i == 1 ? '（死亡）' : '（生存）'
            lines << "  - #{p['name']} : #{role} #{dead_str}"
          end
        end
      rescue => e
        puts "[System Error] Failed to fetch players for epilogue: #{e.message}"
        @game_state.players.each do |name, p|
          lines << "  - #{name} : #{p[:role]} #{p[:dead] == 1 ? '（死亡）' : '（生存）'}"
        end
      end
      lines.join("\n")
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
      
      # 2. 配役コンテキスト生成
      epilogue_ctx = build_epilogue_context(win_msg)
      
      # 3. LLM で感想戦メッセージを生成
      puts "\n[Thinking] Drafting epilogue message..."
      system_prompt = "人狼ゲームが決着しました（#{win_msg}）。ゲーム終了後の感想戦（エピローグ）です。あなたのキャラクター「#{@game_state.my_name}」になりきって、ゲームを終えての感想、楽しかった点、他のプレイヤーへの労いの言葉などを「1文〜2文（合計30〜80文字以内）」で短く自然に発言してください。\n" \
                      "【重要】実際にゲームで起きた出来事や、特定プレイヤーの配役（例:「○○さんが人狼だったとは！」「占い師として頑張りました」など）に具体的に言及してください。抽象的な感想だけでなく、具体的な配役・場面に触れることを強く推奨します。\n" \
                      "【超重要・NGワード】「データ、エミュレーション、システム、共通認識、論理的、変数、感情論、前提、整合性、分析、パラメータ、定量化」などの機械的・論文調・メタ的な言葉は絶対に排除してください。普通の人間として親しみやすく楽しげな感想（例:『楽しかった！』『次は勝ちたいな』など）にしてください。\n" \
                      "発言の冒頭に「#{@game_state.my_name}:」や「#{@game_state.my_name}」などの名前を含めないでください。発言本文のみを出力してください。メタ説明やマークダウン記法、余計な解説は一切含めてはいけません。"
      user_prompt = "ゲームが終了しました。感想戦チャットに最初のメッセージを投稿してください。\n\n#{epilogue_ctx}"
      
      begin
        response = @llm.chat(system_prompt, user_prompt, temperature: 0.8)
        msg = clean_llm_message(response, @game_state.my_name)
        
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
      # 配役コンテキストを動的に生成（感想戦中も毎回参照）
      # win_msg はインスタンス変数で保持していないため、chat_logs から推定
      win_msg = @epilogue_win_msg || "ゲームが終了しました。"
      epilogue_ctx = build_epilogue_context(win_msg)
      system_prompt = "人狼ゲームが終了した後の感想戦（エピローグ）の雑談です。あなたはキャラクター「#{@game_state.my_name}」です。必ず「#{@game_state.my_name}」なりきって発言してください。\n" \
                      "【重要】会話の流れに合わせて、ゲーム中の具体的な出来事や特定プレイヤーの配役（例:「○○さんが人狼だったんですね！」など）に言及してください。以下に全員の配役が記載されています。\n#{epilogue_ctx}\n\n" \
                      "【超重要・発言文字数の制限】1回の返答は必ず「30〜80文字以内（最大でも2文）」で短く簡潔に発言してください。\n" \
                      "【超重要・NGワード】「データ、エミュレーション、システム、共通認識、論理的、変数、感情論、前提、整合性、分析、パラメータ、定量化、発話」といった機械的・システム論的な言葉は絶対に使わないでください。他の参加者とフレンドリーで普通の日常の言葉使い（例:『●●さん強かったですね！』『あの時の投票は〜』など）で雑談してください。\n" \
                      "【重要】発言の冒頭に「#{@game_state.my_name}:」や「#{@game_state.my_name}」などの名前プレフィックスを絶対に含めないでください。会話の発言本文のみを出力してください。【重要】チャットログ内の「#{@game_state.my_name}:」で始まる発言はあなた自身の発言です。自分の発言に対して『#{@game_state.my_name}さんの〜』や『#{@game_state.my_name}さんが言うように〜』といったように、第三者として言及することは絶対に避けてください。他の参加者の発言にのみ反応して、返答・雑談をしてください。"
      user_prompt = "これまでの感想戦チャットログを踏まえて発言してください。\n#{@game_state.formatted_chat_logs}"
      
      begin
        response = @llm.chat(system_prompt, user_prompt, temperature: 0.8)
        msg = clean_llm_message(response, @game_state.my_name)
        
        puts "[Action] AI decided to post epilogue chat: \"#{msg}\""
        post('cmd' => 'msg', 'message' => msg, 'j_data' => 'a')
        @last_say_time = Time.now
      rescue => e
        puts "[System Error] Failed to generate epilogue chat: #{e.message}"
      end
    end
    
    # ゲーム開始前の点呼・待機中の雑談・対話
    def check_and_say_recruiting
      puts "\n[Thinking] Reacting to recruitment chat..."
      system_prompt = "あなたは人狼ゲームのキャラクター「#{@game_state.my_name}」です。ゲーム開始前の待機中（点呼・募集中）の雑談です。キャラクターになりきって、他の参加者の発言に反応したり、ゲーム開始を楽しみにするようなカジュアルな挨拶・日常会話・短い雑談を行ってください。\n" \
                      "【重要】まだゲーム開始前（0日目）で、誰が人狼や役職になるかは一切決まっていません。そのため、特定の役職（占い師、霊媒師等）の希望や、人狼の推理・議論、疑いなどは絶対に言及しないでください。役職に関する言及は完全に排除してください。\n" \
                      "【超重要・発言文字数の制限】1回の返答は必ず「30〜80文字以内（最大でも2文）」で短く簡潔に発言してください。\n" \
                      "【重要】発言の冒頭に「#{@game_state.my_name}:」や「#{@game_state.my_name}」などの名前プレフィックスを絶対に含めないでください。会話の発言本文のみを出力してください。\n" \
                      "【重要】チャットログ内の「#{@game_state.my_name}:」で始まる発言はあなた自身の発言です。自分の発言に対して『#{@game_state.my_name}さんの〜』や『#{@game_state.my_name}さんが言うように〜』といったように、第三者として言及することは絶対に避けてください。他の参加者の発言にのみ反応して、返答・雑談をしてください。"
      user_prompt = "これまでの点呼・待機中チャットログを踏まえて発言してください。\n#{@game_state.formatted_chat_logs}"

      begin
        response = @llm.chat(system_prompt, user_prompt, temperature: 0.8)
        msg = clean_llm_message(response, @game_state.my_name)

        if msg && !msg.strip.empty?
          puts "[Action] AI decided to post recruitment chat: \"#{msg}\""
          post('cmd' => 'msg', 'message' => msg, 'j_data' => 'a')
        else
          puts "[Action] AI skipped recruitment chat (empty response)."
        end
        @last_say_time = Time.now
      rescue => e
        puts "[System Error] Failed to generate recruitment chat: #{e.message}"
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

    # 村の時間の長さの設定や予算モードによって発言頻度を変更する自動調整
    def adjust_talk_intervals!(period)
      # 1. まずベース値と時間伸縮比率の適用
      reactive = @talk_interval_reactive
      active = @talk_interval_active

      if @auto_adjust_talk_interval && period && period > 0
        is_test = @url.include?("localhost") || @url.include?("127.0.0.1")
        unless is_test
          # 基準を10分（10）とする
          ratio = period.to_f / 10.0
          # 1.0 未満にはならないようにする（超短期村でもベースの制限は維持）
          ratio = 1.0 if ratio < 1.0

          reactive = (reactive * ratio).to_i
          active = (active * ratio).to_i
        end
      end

      # 2. 予算モード（budget_mode）による倍率補正の適用
      # low_cost: 2.5倍、max: 0.5倍、normal: 1.0倍
      budget_ratio = case @budget_mode
                     when "low_cost"
                       2.5
                     when "max"
                       0.5
                     else
                       1.0
                     end

      reactive = (reactive * budget_ratio).to_i
      active = (active * budget_ratio).to_i

      # 3. 最低下限値の適用（reactiveは最低2秒、activeは最低5秒）
      reactive = 2 if reactive < 2
      active = 5 if active < 5

      @current_talk_interval_reactive = reactive
      @current_talk_interval_active = active
    end

    def start_async!
      return if @running
      @running = true
      @reflected_and_greeting = false
      @epilogue_start_time = nil
      @voted_today = {}
      @acted_tonight = {}
      @whispered_tonight = {}
      
      @client_thread = Thread.new do
        begin
          login!
          vid = @vid
          already_joined = find_active_joined_village
          
          if @running && !already_joined
            if vid.nil? || vid == 0
              auto_entry_loop!
            else
              @vid = vid
              puts "[System] Target village ID: #{@vid}. Checking entry status..."
              entry_ok = false
              30.times do |i|
                break unless @running
                if entry_to_village!
                  entry_ok = true
                  break
                end
                puts "  Waiting for village ID #{@vid} to be created or available... (#{i+1}/30)"
                sleep 5
              end
              if @running && !entry_ok
                puts "[System] Active entry failed. Falling back to auto-entry monitoring..."
                @vid = nil
                auto_entry_loop!
              end
            end
          end
          
          if @running
            init_game_state!
            start_loop!
          end
        rescue => e
          puts "[System Error] Error in client async thread: #{e.class} - #{e.message}"
          puts e.backtrace.join("\n")
        ensure
          @running = false
        end
      end
    end

    def stop!
      return unless @running
      puts "[System] Stopping client..."
      @running = false
      
      if @client_thread
        @client_thread.join(2)
        if @client_thread.alive?
          @client_thread.kill
        end
        @client_thread = nil
      end
      puts "[System] Client stopped."
    end

    def reload_config!
      puts "[System] Reloading configuration from #{@config_path}..."
      @config = Client.load_config(@config_path)
      
      server_config = @config['server'] || {}
      @url = server_config['url']
      if @url
        @url = @url.sub(/\/aiwolf\/?\z/, '').chomp('/')
      end
      @vid = server_config['vid']
      
      user_config = @config['user'] || {}
      @userid = user_config['userid']
      @password = user_config['password']
      
      @llm = LLMClient.new(@config)
      
      @compact_prompt = @config.dig('llm', 'compact_prompt') != false
      @talk_interval_reactive = @config.dig('llm', 'talk_interval_reactive') || 10
      @talk_interval_active = @config.dig('llm', 'talk_interval_active') || 60
      @auto_adjust_talk_interval = @config.dig('llm', 'auto_adjust_talk_interval') != false
      @budget_mode = @config.dig('llm', 'budget_mode') || 'normal'
      @anchor_resolution = @config.dig('llm', 'anchor_resolution') != false
      
      @game_state.my_name = @userid if @game_state
      
      puts "[System] Configuration reloaded successfully."
    rescue => e
      puts "[System Error] Failed to reload configuration: #{e.message}"
    end
  end
end
