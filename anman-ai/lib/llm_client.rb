# -*- coding: utf-8 -*-
require_relative 'llm/ollama_adapter'
require_relative 'llm/openai_compat_adapter'
require_relative 'llm/gemini_adapter'

module AnmanAI
  class LLMClient
    attr_reader :model

    def initialize(config)
      @main_adapter = build_adapter(config['llm'])
      @fallback_adapter = build_adapter(config['llm_fallback'])
      @model = config.dig('llm', 'model')
    end

    def chat(system_prompt, user_prompt, temperature: 0.7, max_retries: 2)
      raw_res = begin
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

      if raw_res
        raw_res = raw_res.gsub(/<think>.*?<\/think>/mi, '').strip
      end
      raw_res
    end

    private

    def build_adapter(llm_config)
      return nil unless llm_config
      
      provider = llm_config['provider']
      if provider.nil? || provider.to_s.strip.empty?
        # Auto-detect: If an API key is present (and it's not "ollama"), assume openai_compat or gemini
        api_key = llm_config['api_key']
        if api_key && !api_key.to_s.strip.empty? && api_key != 'ollama'
          if api_key.to_s.start_with?('AIzaSy')
            provider = 'gemini'
          else
            provider = 'openai_compat'
          end
        else
          provider = 'ollama'
        end
      end

      # Adapters expect config.dig('llm', ...), so construct a pseudo config hash
      pseudo_config = { 'llm' => llm_config }

      case provider.to_s.downcase
      when 'ollama'
        LLM::OllamaAdapter.new(pseudo_config)
      when 'openai_compat'
        LLM::OpenAICompatAdapter.new(pseudo_config)
      when 'gemini', 'google'
        LLM::GeminiAdapter.new(pseudo_config)
      else
        STDERR.puts "[LLM Warning] Unknown provider '#{provider}', falling back to Ollama adapter."
        LLM::OllamaAdapter.new(pseudo_config)
      end
    end
  end
end
