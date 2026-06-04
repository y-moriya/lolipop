require 'json'
require 'fileutils'

module AnmanAI
  class LearningSystem
    def initialize(root_dir, llm_client)
      @root_dir = root_dir
      @llm_client = llm_client
      @store_path = File.join(root_dir, 'memory', 'learning_store.json')
      FileUtils.mkdir_p(File.dirname(@store_path))
    end

    # プロンプト注入用の学習メモリテキストの生成
    def load_memory_text
      unless File.exist?(@store_path)
        return "（過去の学習データはまだありません。今日のゲームプレイに集中してください）"
      end

      begin
        content = File.read(@store_path)
        records = JSON.parse(content)
        return "（過去の学習データはまだありません）" if records.empty?

        # 直近の最大5ゲームの反省点を出力用にまとめる
        text = "過去のゲームプレイから得られた反省点と改善アクション:\n"
        records.last(5).each do |rec|
          text += "- 村##{rec['vid']} (役職: #{rec['role']}, 結果: #{rec['result']}):\n"
          (rec['key_findings'] || []).each do |finding|
            text += "  * #{finding}\n"
          end
        end
        text
      rescue => e
        "（過去の学習データの読み込みに失敗しました: #{e.message}）"
      end
    end

    # ゲーム終了時の反省処理を実行
    def run_reflection(vid, my_role, won, all_logs_text)
      result = won ? "勝利 (Won)" : "敗北 (Lost)"

      system_prompt = "あなたは人狼ゲームの熟練プレイヤー兼アナリストです。客観的かつ厳密にゲームプレイの反省・分析を行います。"
      user_prompt = <<~EOF
        あなたは人狼ゲームプレイヤー「anman-ai」です。先ほど参加したゲーム（村ID: #{vid}）が終了しました。
        あなたの役職は #{my_role} でした。ゲーム結果は #{result} です。

        以下は、このゲームの全ログです。
        ---
        #{all_logs_text}
        ---

        このログを分析し、あなたのプレイについての反省（ポストモーテム分析）を行ってください。
        以下の点に注目して分析してください：
        1. あなたの良かった行動、発言、意思決定。
        2. あなたの悪かった行動（ミス、不自然な発言、投票ミス、COの遅れなど）。
        3. 次回から改善すべき具体的な行動指針やプレイスタイルのヒント。

        出力は必ず以下のJSONフォーマットのみとし、マークダウンのコードブロック（```json ... ```）等も使用せず、プレーンなJSONオブジェクト1件のみを出力してください。余計な説明や挨拶は含めないでください。
        {
          "key_findings": [
            "（得られた知見や反省点、次回への改善アクション。箇ラ書きで3〜5件程度）"
          ]
        }
      EOF

      begin
        response = @llm_client.chat(system_prompt, user_prompt, temperature: 0.3)
        
        # マークダウンのコードブロック表記があれば除去
        clean_response = response.gsub(/^```json\s*/, "").gsub(/```\s*$/, "").strip
        parsed = JSON.parse(clean_response)
        findings = parsed['key_findings'] || []

        # 既存のデータをロードして追記
        records = File.exist?(@store_path) ? JSON.parse(File.read(@store_path)) : []
        records << {
          'vid' => vid,
          'role' => my_role,
          'result' => result,
          'key_findings' => findings,
          'timestamp' => Time.now.strftime("%Y/%m/%d %H:%M:%S")
        }

        # 保存
        File.write(@store_path, JSON.pretty_generate(records))
        true
      rescue => e
        # ゲーム進行を妨げないよう、エラーは stderr に出力して無視する
        STDERR.puts "[Reflection Error] Failed to generate reflection for village #{vid}: #{e.message}"
        false
      end
    end
  end
end
