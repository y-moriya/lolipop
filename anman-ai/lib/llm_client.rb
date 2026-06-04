require 'net/http'
require 'uri'
require 'json'

module AnmanAI
  class LLMClient
    attr_reader :model

    def initialize(config)
      @api_key = ENV['ANMAN_LLM_API_KEY'] || config.dig('llm', 'api_key')
      @base_url = config.dig('llm', 'base_url')
      @model = config.dig('llm', 'model')
    end

    def chat(system_prompt, user_prompt, temperature: 0.7)
      uri = URI.parse("#{@base_url}/chat/completions")
      
      # URLパスの修正（Ollama等でパスが空になるのを防ぐため、フルパスを扱う）
      path = uri.path.empty? ? "/v1/chat/completions" : uri.path
      
      header = {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{@api_key}"
      }
      
      body = {
        model: @model,
        messages: [
          { role: 'system', content: system_prompt },
          { role: 'user', content: user_prompt }
        ],
        temperature: temperature
      }

      req = Net::HTTP::Post.new(path, header)
      req.body = body.to_json

      # HTTPS接続の判定
      use_ssl = uri.scheme == 'https'

      begin
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: use_ssl) do |http|
          http.read_timeout = 90 # LLM生成を考慮しタイムアウトは長め
          http.open_timeout = 5  # 接続タイムアウト
          http.request(req)
        end

        if res.code == '200'
          data = JSON.parse(res.body)
          data.dig('choices', 0, 'message', 'content')
        else
          raise "LLM API Error: #{res.code} - #{res.body}"
        end
      rescue => e
        raise "LLM Client Connection Error: #{e.message}"
      end
    end
  end
end
