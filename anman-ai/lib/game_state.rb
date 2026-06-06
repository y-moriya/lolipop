module AnmanAI
  class GameState
    attr_accessor :current_day, :is_night, :my_name, :my_role, :my_reasoning_notes,
                  :players, :chat_logs, :action_results, :werewolf_partners,
                  :game_started

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
      @game_started = false

      # --- コンパクトプロンプト用 ---
      # ゲームの重要イベントを蓄積して要約文を生成する
      @key_events = []          # 重要イベント of テキストリスト
      @last_sent_event_id = 0   # 最後にLLMへ送ったイベントID（差分ログ用）
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
        @my_role = current_player_json['role'] || "未決定"

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
        # 配役発表（村開始メッセージ）を検知
        if content.include?("どうやらこの村には")
          @game_started = true
        end

        # 処刑： "投票の結果、XXX が処刑されました。"
        if content =~ /^(?:投票の結果、)?(.*?) が処刑されました。/
          mark_as_dead($1)
          add_key_event("#{@current_day}日目: #{$1.strip} が処刑されました。")
        # 襲撃： "XXX が無残な姿で発見されました。"
        elsif content =~ /^(.*?) が無残な姿で発見されました。/
          mark_as_dead($1)
          add_key_event("#{@current_day}日目: #{$1.strip} が人狼に襲撃されました。")
        # 突然死
        elsif content =~ /^(.*?) が突然死しました。/
          mark_as_dead($1)
          add_key_event("#{@current_day}日目: #{$1.strip} が突然死しました。")
        # 占い結果（自分が受け取った場合）
        elsif content =~ /(.+?) は、(.+?) を占いました。\n(.+?) は (.+?)のようです。/
          msg = "#{@current_day}日目: 占い結果 — #{$2.strip} は #{$4.strip}"
          add_key_event(msg)
          @action_results << msg unless @action_results.include?(msg)
        elsif content.include?("の勝利です")
          add_key_event("ゲーム終了: #{content.strip}")
        end
      end

      # 自分の夜アクションのターゲット設定イベントを検知・復元
      if e['type'] == 'system' && e['type_code'] == 'think' && e['is_mine']
        content = e['content']
        if content =~ /占います。/ || content =~ /護衛します。/ || content =~ /襲撃します。/ || content =~ /愛を求めます。/ || content =~ /邪魔をします。/
          msg = "#{@current_day}日目夜: #{content}"
          @action_results << msg unless @action_results.include?(msg)
        end
      end

      # 進行ブロックから昼夜変更を判別
      if e['type'] == 'state_change' && e['type_code'] == 'time'
        content = e['content']
        if content.include?("夜になりました")
          @is_night = true
          add_key_event("#{@current_day}日目: 夜フェーズ開始")
        elsif content.include?("朝になりました") || content.include?("昼になりました") || content.include?("話し合い")
          @is_night = false
          add_key_event("#{@current_day}日目: 昼フェーズ開始（話し合い）")
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
      # メモリ節約・コンテキスト長抑制のため直近30件に制限
      @chat_logs.shift if @chat_logs.size > 30
    end

    # 重要イベントをサマリーに追記（最大30件）
    def add_key_event(text)
      @key_events << text
      @key_events.shift if @key_events.size > 30
    end

    # ============================================================
    # コンパクトプロンプト用メソッド群
    # ============================================================

    # ゲームの状況サマリー（重要イベントの記録）
    # compact_prompt モード時にチャットログ全量の代わりに渡す
    def game_summary
      lines = []
      lines << "【ゲーム経過サマリー】"
      if @key_events.empty?
        lines << "  （ゲーム開始直後のため、まだ重要イベントはありません）"
      else
        @key_events.each { |ev| lines << "  #{ev}" }
      end
      lines << ""
      lines << "【占い・夜アクション結果】"
      if @action_results.empty?
        lines << "  特になし"
      else
        @action_results.each { |r| lines << "  #{r}" }
      end
      lines.join("\n")
    end

    # 最後にLLMへ送ったイベントID以降の差分チャットログのみを返す
    def incremental_chat_logs
      new_logs = @chat_logs.select { |log| log['id'].to_i > @last_sent_event_id }
      return "（新着チャットなし）" if new_logs.empty?

      new_logs.map { |log| format_log_line(log) }.join("\n")
    end

    # LLM呼び出し後に実行。「ここまで送信済み」マークを更新する
    def mark_logs_sent!
      return if @chat_logs.empty?
      max_id = @chat_logs.map { |log| log['id'].to_i }.max
      @last_sent_event_id = max_id if max_id > @last_sent_event_id
    end

    # ============================================================
    # プロンプト用シリアライズメソッド群
    # ============================================================

    def surviving_players_list
      @players.select { |name, p| p[:dead] == 0 && name != @my_name }.keys.join(", ")
    end

    def dead_players_list
      list = @players.select { |name, p| p[:dead] == 1 }.keys
      list.empty? ? "なし" : list.join(", ")
    end

    # 全チャットログをフォーマット（compact_prompt=false 時に使用）
    def formatted_chat_logs
      @chat_logs.map { |log| format_log_line(log) }.join("\n")
    end

    # 自分の直近N件の発言テキストを返す（繰り返し防止用）
    def my_recent_says(n = 5)
      my_says = @chat_logs.select do |log|
        log['type'] == 'message' &&
          ['say', 'think', 'groan'].include?(log['type_code']) &&
          log['speaker'] == @my_name
      end.last(n)
      return "（まだ発言なし）" if my_says.empty?
      my_says.map { |log| "- #{log['content']}" }.join("\n")
    end

    def formatted_action_results
      @action_results.empty? ? "特になし" : @action_results.join("\n")
    end

    private

    # ログ1件をテキスト行にフォーマット（全メソッド共通）
    def format_log_line(log)
      time_part = log['time'] ? "[#{log['time']}] " : ""
      case log['type']
      when 'message'
        tc = log['type_code']
        # クライアント側の安全装置: 自分が人狼・狂信者等ではない場合、ささやき(whisper/whisperhowl)は常にマスクする
        is_werewolf_camp = ["人狼", "狂信者"].include?(@my_role) || !@werewolf_partners.empty?
        if (tc == 'whisper' || tc == 'whisperhowl') && !is_werewolf_camp
          "#{time_part}[システム] 狼の遠吠え: わおーん"
        else
          label = tc == 'say' ? "" : " (#{tc})"
          "#{time_part}#{log['speaker']}#{label}: #{log['content']}"
        end
      when 'system'
        "#{time_part}[システム]: #{log['content']}"
      when 'state_change'
        "#{time_part}[進行]: #{log['content']}"
      else
        "#{time_part}#{log['content']}"
      end
    end
  end
end
