# -*- coding: utf-8 -*-
require_relative 'llm/ollama_adapter'
require_relative 'llm/openai_compat_adapter'

module AnmanAI
  class LLMClient
    attr_reader :model

    def initialize(config)
      provider = config.dig('llm', 'provider') || 'ollama'
      @model = config.dig('llm', 'model')

      case provider
      when 'ollama'
        @adapter = LLM::OllamaAdapter.new(config)
      when 'openai_compat'
        @adapter = LLM::OpenAICompatAdapter.new(config)
      else
        STDERR.puts "[LLM Warning] Unknown provider '#{provider}', falling back to Ollama adapter."
        @adapter = LLM::OllamaAdapter.new(config)
      end
    end

    def chat(system_prompt, user_prompt, temperature: 0.7, max_retries: 2)
      @adapter.chat(system_prompt, user_prompt, temperature: temperature, max_retries: max_retries)
    end
  end
end
