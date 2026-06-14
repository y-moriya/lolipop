# -*- coding: utf-8 -*-
require 'webrick'
require 'json'
require 'yaml'
require 'net/http'
require 'uri'

module AnmanAI
  class WebServer
    def initialize(client, exe_dir, internal_root_dir)
      @client = client
      @exe_dir = exe_dir
      @internal_root_dir = internal_root_dir
      
      # WEBrick サーバーの初期化
      # 外部にポートが不要に露出しないようにローカルホスト（127.0.0.1）にバインド
      @server = WEBrick::HTTPServer.new(
        BindAddress: '127.0.0.1',
        Port: 8064,
        DocumentRoot: File.join(internal_root_dir, 'public'),
        AccessLog: [],
        Logger: WEBrick::Log.new(nil, WEBrick::BasicLog::WARN)
      )
      
      setup_routes
    end

    def start
      @server_thread = Thread.new do
        begin
          @server.start
        rescue => e
          puts "[Web Server Error] WEBrick failed to start: #{e.message}"
        end
      end
    end

    def stop
      @server.shutdown
      @server_thread.join if @server_thread
    end

    private

    def setup_routes
      # 全てのリクエストに対してCORSヘッダーを追加し、APIをマウント
      @server.mount_proc '/api' do |req, res|
        res['Access-Control-Allow-Origin'] = '*'
        res['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
        res['Access-Control-Allow-Headers'] = 'Content-Type'
        
        if req.request_method == 'OPTIONS'
          res.status = 200
          next
        end

        res.content_type = 'application/json'
        
        case req.path
        when '/api/status'
          handle_status(req, res)
        when '/api/test_llm'
          if req.request_method == 'POST'
            handle_test_llm(req, res)
          end
        when '/api/update'
          if req.request_method == 'POST'
            handle_update(req, res)
          end
        when '/api/config'
          if req.request_method == 'GET'
            handle_get_config(req, res)
          elsif req.request_method == 'POST'
            handle_post_config(req, res)
          end
        when '/api/start'
          handle_start(req, res)
        when '/api/stop'
          handle_stop(req, res)
        when '/api/logs'
          handle_logs(req, res)
        when '/api/game_state'
          handle_game_state(req, res)
        else
          res.status = 404
          res.body = { error: 'Not Found' }.to_json
        end
      end
    end

    def handle_status(req, res)
      status = {
        running: @client.running,
        version: AnmanAI::VERSION,
        my_name: @client.game_state&.my_name || @client.userid,
        my_role: @client.game_state&.my_role || "不明",
        vid: @client.vid,
        url: @client.url,
        game_started: @client.game_state&.game_started || false
      }
      res.body = status.to_json
    end

    def handle_get_config(req, res)
      config_path = @client.config_path
      config = YAML.load_file(config_path) rescue {}
      
      # llm_configがあれば外部ファイルからもLLM設定を読み込んでマージ
      if config['llm_config']
        config_dir = File.dirname(config_path)
        llm_config_path = File.expand_path(config['llm_config'], config_dir)
        if File.exist?(llm_config_path)
          llm_config = YAML.load_file(llm_config_path) rescue {}
          config['llm'] = llm_config['llm'] if llm_config['llm']
          config['llm_fallback'] = llm_config['llm_fallback'] if llm_config['llm_fallback']
        end
      end
      
      res.body = config.to_json
    end

    def handle_post_config(req, res)
      begin
        data = JSON.parse(req.body)
        config_path = @client.config_path
        config_dir = File.dirname(config_path)
        
        # 既存のconfig.yamlをロードして構造を維持
        current_config = YAML.load_file(config_path) rescue {}
        
        # 送信されたデータで更新
        current_config['server'] ||= {}
        current_config['server']['url'] = data.dig('server', 'url') if data.dig('server', 'url')
        current_config['server']['vid'] = data.dig('server', 'vid').to_i if data.dig('server', 'vid')
        current_config['server']['pass'] = data.dig('server', 'pass') if data.dig('server', 'pass')
        current_config['server']['epilogue_timeout'] = data.dig('server', 'epilogue_timeout').to_i if data.dig('server', 'epilogue_timeout')
        
        current_config['user'] ||= {}
        current_config['user']['userid'] = data.dig('user', 'userid') if data.dig('user', 'userid')
        current_config['user']['password'] = data.dig('user', 'password') if data.dig('user', 'password')
        
        current_config['log'] ||= {}
        current_config['log']['max_size_mb'] = data.dig('log', 'max_size_mb').to_i if data.dig('log', 'max_size_mb')
        current_config['log']['keep_files'] = data.dig('log', 'keep_files').to_i if data.dig('log', 'keep_files')
        
        # LLM設定の書き出し
        llm_data = data['llm'] || {}
        llm_fallback_data = data['llm_fallback']
        
        if current_config['llm_config']
          # 外部ファイル構成の場合
          llm_config_path = File.expand_path(current_config['llm_config'], config_dir)
          external_llm_config = {
            'llm' => llm_data
          }
          external_llm_config['llm_fallback'] = llm_fallback_data if llm_fallback_data
          
          File.write(llm_config_path, YAML.dump(external_llm_config))
        else
          # 直接 config.yaml に書く場合
          current_config['llm'] = llm_data
          if llm_fallback_data
            current_config['llm_fallback'] = llm_fallback_data
          else
            current_config.delete('llm_fallback')
          end
        end
        
        # config.yamlの保存
        File.write(config_path, YAML.dump(current_config))
        
        # クライアントの設定リロード
        @client.reload_config!
        
        res.body = { success: true }.to_json
      rescue => e
        res.status = 500
        res.body = { error: e.message }.to_json
      end
    end

    def handle_start(req, res)
      if @client.running
        res.body = { success: true, message: "Already running" }.to_json
      else
        @client.start_async!
        res.body = { success: true }.to_json
      end
    end

    def handle_stop(req, res)
      if @client.running
        @client.stop!
        res.body = { success: true }.to_json
      else
        res.body = { success: true, message: "Already stopped" }.to_json
      end
    end

    def handle_logs(req, res)
      log_path = File.join(@exe_dir, 'log', 'anman-ai.log')
      lines_to_read = (req.query['lines'] || 100).to_i
      
      if File.exist?(log_path)
        lines = []
        File.open(log_path, 'r') do |f|
          # UTF-8 で開くが、不正な文字は置換するようにする
          f.set_encoding('UTF-8', invalid: :replace, undef: :replace)
          all_lines = f.readlines
          lines = all_lines.last(lines_to_read)
        end
        res.body = { success: true, logs: lines }.to_json
      else
        res.body = { success: false, error: "Log file not found" }.to_json
      end
    end

    def handle_game_state(req, res)
      gs = @client.game_state
      if gs
        players_formatted = {}
        gs.players.each do |name, p|
          players_formatted[name] = {
            userid: p[:userid],
            num_id: p[:num_id],
            dead: p[:dead],
            role: p[:role]
          }
        end

        state_data = {
          current_day: gs.current_day,
          is_night: gs.is_night,
          my_name: gs.my_name,
          my_role: gs.my_role,
          my_reasoning_notes: gs.my_reasoning_notes,
          players: players_formatted,
          chat_logs: gs.chat_logs,
          action_results: gs.action_results,
          werewolf_partners: gs.werewolf_partners,
          game_started: gs.game_started,
          summary: gs.game_summary
        }
        res.body = state_data.to_json
      else
        res.body = { success: false, error: "Game state not initialized" }.to_json
      end
    end

    def handle_test_llm(req, res)
      begin
        data = JSON.parse(req.body)
        provider = data['provider']
        api_key = data['api_key']
        model = data['model']
        base_url = data['base_url']

        resolved_api_key = api_key
        if resolved_api_key.nil? || resolved_api_key.to_s.strip.empty?
          resolved_api_key = ENV['GEMINI_API_KEY'] || ENV['ANMAN_GEMINI_API_KEY'] if provider == 'gemini'
          resolved_api_key = ENV['ANMAN_LLM_API_KEY'] if provider == 'openai_compat' || provider == 'ollama'
        end

        success = false
        message = ""

        case provider
        when 'gemini'
          if resolved_api_key.nil? || resolved_api_key.to_s.strip.empty?
            raise "Gemini API Key is missing. Please set it in settings or environment."
          end
          url = base_url.to_s.strip.empty? ? "https://generativelanguage.googleapis.com" : base_url
          uri = URI.parse("#{url.sub(/\/+$/, '')}/v1beta/models?key=#{resolved_api_key}")
          
          http_res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
            http.read_timeout = 15
            http.open_timeout = 10
            http.get(uri.request_uri)
          end

          if http_res.code == '200'
            success = true
            message = "接続成功: モデルリストが正常に取得できました。"
          else
            raise "HTTP #{http_res.code}: #{http_res.body[0..300]}"
          end

        when 'openai_compat'
          url = base_url.to_s.strip.empty? ? "https://api.openai.com/v1" : base_url
          base_uri = URI.parse(url)
          path = base_uri.path.to_s.sub(/\/+$/, '')
          unless path.end_with?('/v1') || path.end_with?('/v1/')
            path = path.sub(/\/chat\/completions\z/, '')
            path += '/v1' unless path.end_with?('/v1')
          end
          port_part = base_uri.port && base_uri.port != 80 && base_uri.port != 443 ? ":#{base_uri.port}" : ""
          target_url = "#{base_uri.scheme}://#{base_uri.host}#{port_part}#{path}/models"
          uri = URI.parse(target_url)

          req_obj = Net::HTTP::Get.new(uri.request_uri)
          req_obj['Authorization'] = "Bearer #{resolved_api_key}" if resolved_api_key && !resolved_api_key.to_s.strip.empty?

          http_res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
            http.read_timeout = 15
            http.open_timeout = 10
            http.request(req_obj)
          end

          if http_res.code == '200'
            success = true
            message = "接続成功: モデルリストが正常に取得できました。"
          else
            raise "HTTP #{http_res.code}: #{http_res.body[0..300]}"
          end

        when 'ollama'
          url = base_url.to_s.strip.empty? ? "http://localhost:11434" : base_url
          base_uri = URI.parse(url)
          # handle potential path on Ollama
          port_part = base_uri.port ? ":#{base_uri.port}" : ""
          target_url = "#{base_uri.scheme}://#{base_uri.host}#{port_part}/api/tags"
          uri = URI.parse(target_url)

          req_obj = Net::HTTP::Get.new(uri.path)
          req_obj['Authorization'] = "Bearer #{resolved_api_key}" if resolved_api_key && !resolved_api_key.to_s.strip.empty?

          begin
            http_res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
              http.read_timeout = 15
              http.open_timeout = 5
              http.request(req_obj)
            end
          rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Net::OpenTimeout => e
            if uri.host == 'localhost' || uri.host == '127.0.0.1'
              ips = []
              begin
                `ip route`.split("\n").each do |line|
                  ips << $1 if line =~ /default via (\S+)/
                end
              rescue
              end
              begin
                if File.exist?('/etc/resolv.conf')
                  File.readlines('/etc/resolv.conf').each do |line|
                    ips << $1 if line =~ /^\s*nameserver\s+(\S+)/
                  end
                end
              rescue
              end
              ips = ips.uniq

              successful_host = nil
              ips.each do |ip|
                begin
                  Net::HTTP.start(ip, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 2) do |http|
                    check_res = http.get('/api/tags')
                    if check_res.code == '200'
                      successful_host = ip
                      break
                    end
                  end
                rescue
                end
              end

              if successful_host
                uri.host = successful_host
                retry
              end
            end
            raise e
          end

          if http_res.code == '200'
            success = true
            message = "接続成功: Ollamaが起動しており、モデルリストを取得できました。"
          else
            raise "HTTP #{http_res.code}: #{http_res.body[0..300]}"
          end
        else
          raise "Unknown provider: #{provider}"
        end

        res.body = { success: success, message: message }.to_json
      rescue => e
        res.body = { success: false, error: e.message }.to_json
      end
    end

    def handle_update(req, res)
      begin
        require 'updater'
        # Run update asynchronously to allow HTTP response to complete first
        Thread.new do
          sleep 1.0
          AnmanAI::Updater.run(@exe_dir)
          exit 0
        end
        res.body = { success: true, message: "アップデートを開始しました。数秒後に自動で再起動されます。" }.to_json
      rescue => e
        res.status = 500
        res.body = { success: false, error: e.message }.to_json
      end
    end
  end
end
