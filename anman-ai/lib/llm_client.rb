# -*- coding: utf-8 -*-
require_relative 'llm/ollama_adapter'
require_relative 'llm/openai_compat_adapter'

module AnmanAI
  class LLMClient
    attr_reader :model

    def initialize(config)
      @main_adapter = build_adapter(config['llm'])
      @fallback_adapter = build_adapter(config['llm_fallback'])
      @model = config.dig('llm', 'model')
    end

    def chat(system_prompt, user_prompt, temperature: 0.7, max_retries: 2)
      begin
        @main_adapter.chat(system_prompt, user_prompt, temperature: temperature, max_retries: max_retries)
      rescue => e
        if @fallback_adapter
          STDERR.puts "[LLM Warning] Main LLM failed: #{e.message}. Trying fallback LLM..."
          begin
            @fallback_adapter.chat(system_prompt, user_prompt, temperature: temperature, max_retries: max_retries)
          rescue => fallback_err
            STDERR.puts "[LLM Error] Fallback LLM also failed: #{fallback_err.message}"
            raise fallback_err
          end
        else
          raise e
        end
      end
    end

    private

    def build_adapter(llm_config)
      return nil unless llm_config
      provider = llm_config['provider'] || 'ollama'

      # Adapters expect config.dig('llm', ...), so construct a pseudo config hash
      pseudo_config = { 'llm' => llm_config }

      case provider
      when 'ollama'
        LLM::OllamaAdapter.new(pseudo_config)
      when 'openai_compat'
        LLM::OpenAICompatAdapter.new(pseudo_config)
      else
        STDERR.puts "[LLM Warning] Unknown provider '#{provider}', falling back to Ollama adapter."
        LLM::OllamaAdapter.new(pseudo_config)
      end
    end
  end
end
