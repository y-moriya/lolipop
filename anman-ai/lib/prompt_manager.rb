require 'yaml'

module AnmanAI
  class PromptManager
    def initialize(exe_dir, internal_root_dir)
      @exe_dir = exe_dir
      @internal_root_dir = internal_root_dir
      reload_personality
    end

    def reload_personality
      personality_path = File.join(@exe_dir, 'config', 'personality.yaml')
      unless File.exist?(personality_path)
        personality_path = File.join(@internal_root_dir, 'config', 'personality.yaml')
      end

      if File.exist?(personality_path)
        @personality = YAML.load_file(personality_path)
      else
        @personality = {
          'base_instructions' => "- あなたは「anman-ai」という人狼プレイヤーです。\n- 論理的に会話を行ってください。"
        }
      end
    end

    def base_instructions
      @personality['base_instructions']
    end

    # 陣営に応じた基本思考ガイドを読み込む (camp: 'villager' または 'werewolf')
    def load_camp_prompt(camp)
      file_path = File.join(@internal_root_dir, 'prompts', 'base', "#{camp}.txt")
      File.exist?(file_path) ? File.read(file_path) : ""
    end

    # 状況別プロンプトの読み込みとプレースホルダ置換
    def build_prompt(situation, variables)
      template_path = File.join(@internal_root_dir, 'prompts', 'situations', "#{situation}.txt")
      raise "Prompt template not found for situation: #{situation}" unless File.exist?(template_path)

      prompt = File.read(template_path)

      # 共通の変数をデフォルト設定
      full_vars = {
        'base_instructions' => base_instructions,
        'learning_memory' => "（過去の試合からの具体的な反省点や学習データはまだありません。今日のゲームプレイに集中してください）"
      }.merge(variables)

      # {{variable_name}} を実際の値に置換
      full_vars.each do |key, val|
        prompt.gsub!("{{#{key}}}", val.to_s)
      end

      prompt
    end
  end
end
