module AnmanAI
  class GameState
    attr_accessor :current_day, :is_night, :my_name, :my_role, :my_reasoning_notes, :players, :chat_logs, :action_results, :werewolf_partners

    def initialize(my_name)
      @my_name = my_name
      @my_role = "不明"
      @current_day = 1
      @is_night = false
      @players = {} # { "名前" => { num_id: X, dead: 0/1, role: "不明" } }
      @chat_logs = []
      @action_results = []
      @my_reasoning_notes = "特になし。怪しいプレイヤーのリストアップやカミングアウト（CO）のタイミングを整理してください。"
      @werewolf_partners = []
    end

    # 初期プレイヤー情報を設定 (cmd=players のレスポンスを反映)
    def init_players(players_json, current_player_json)
      @players.clear
      players_json.each do |p|
        name = p['name']
        @players[name] = {
          userid: p['userid'],
          num_id: p['num_id'].to_i,
          dead: p['dead'].to_i,
          role: "不明"
        }
      end

      if current_player_json
        @my_name = current_player_json['name']
        @my_role = current_player_json['role'] || "村人"
        
        # 自分が人狼の場合、他の人狼メンバーを探す
        if current_player_json['can_whisper']
          @werewolf_partners = players_json.select { |p| 
            p['userid'] != current_player_json['userid'] && p['role'] == "人狼"
          }.map { |p| p['name'] }
        end
      end
    end

    # イベントを受信して状態を更新
    def process_event(e)
      add_chat_log(e)

      @current_day = e['day'].to_i if e['day']

      # システムメッセージから生死などを判別
      if e['type'] == 'system' && e['type_code'] == 'announce'
        content = e['content']
        # 処刑： "XXX が処刑されました。"
        if content =~ /^(.*?) が処刑されました。/
          mark_as_dead($1)
        # 襲撃： "XXX が無残な姿で発見されました。"
        elsif content =~ /^(.*?) が無残な姿で発見されました。/
          mark_as_dead($1)
        # 突然死： "XXX が突然死しました。"
        elsif content =~ /^(.*?) が突然死しました。/
          mark_as_dead($1)
        end
      end

      # 進行ブロックから昼夜変更を判別
      if e['type'] == 'state_change' && e['type_code'] == 'time'
        content = e['content']
        if content.include?("夜になりました")
          @is_night = true
        elsif content.include?("朝になりました") || content.include?("昼になりました") || content.include?("話し合い")
          @is_night = false
        end
      end
    end

    def mark_as_dead(name)
      name = name.strip
      if @players[name]
        @players[name][:dead] = 1
      end
    end

    def add_chat_log(e)
      # 重複登録の防止
      return if @chat_logs.any? { |log| log['id'] == e['id'] }
      @chat_logs << e
      # メモリ節約のため直近100件程度に制限
      @chat_logs.shift if @chat_logs.size > 100
    end

    # プロンプト用のシリアライズメソッド群
    def surviving_players_list
      @players.select { |name, p| p[:dead] == 0 && name != @my_name }.keys.join(", ")
    end

    def dead_players_list
      list = @players.select { |name, p| p[:dead] == 1 }.keys
      list.empty? ? "なし" : list.join(", ")
    end

    def formatted_chat_logs
      logs = @chat_logs.map do |log|
        time_part = log['time'] ? "[#{log['time']}] " : ""
        case log['type']
        when 'message'
          label = log['type_code'] == 'say' ? "" : " (#{log['type_code']})"
          "#{time_part}#{log['speaker']}#{label}: #{log['content']}"
        when 'system'
          "#{time_part}[システム]: #{log['content']}"
        when 'state_change'
          "#{time_part}[進行]: #{log['content']}"
        else
          "#{time_part}#{log['content']}"
        end
      end
      logs.join("\n")
    end

    def formatted_action_results
      @action_results.empty? ? "特になし" : @action_results.join("\n")
    end
  end
end
