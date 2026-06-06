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

    def chat(system_prompt, user_prompt, temperature: 0.7, max_retries: 2)
      uri  = URI.parse("#{@base_url}/chat/completions")
      path = uri.path.empty? ? "/v1/chat/completions" : uri.path

      header = {
        'Content-Type'  => 'application/json',
        'Authorization' => "Bearer #{@api_key}"
      }

      body = {
        model:       @model,
        messages:    [
          { role: 'system', content: system_prompt },
          { role: 'user',   content: user_prompt }
        ],
        temperature: temperature,
        max_tokens:  2048,  # 出力トークン上限
        options: {
          num_ctx: 8192   # Ollamaのデフォルトnum_ctx(2048)を上書きしプロンプト長超過を防ぐ
        }
      }

      req      = Net::HTTP::Post.new(path, header)
      req.body = body.to_json
      use_ssl  = uri.scheme == 'https'

      last_error = nil
      (max_retries + 1).times do |attempt|
        begin
          res = Net::HTTP.start(uri.host, uri.port, use_ssl: use_ssl) do |http|
            http.read_timeout = 90
            http.open_timeout = 15  # Ollamaコールドスタート対応
            http.request(req)
          end

          if res.code == '200'
            data    = JSON.parse(res.body)
            content = data.dig('choices', 0, 'message', 'content')
            # 空レスポンスはリトライ対象（gemma4がコンテキスト長超過時に返すケース）
            if content.nil? || content.strip.empty?
              last_error = "LLM returned empty response (attempt #{attempt + 1}/#{max_retries + 1})"
              STDERR.puts "[LLM Warning] #{last_error}"
              sleep 1
              next
            end
            return content
          else
            raise "LLM API Error: #{res.code} - #{res.body[0..200]}"
          end
        rescue => e
          last_error = e.message
          raise "LLM Client Connection Error: #{e.message}" unless e.message.include?("empty response")
          sleep 1
        end
      end

      raise "LLM Client Error: #{last_error}"
    end
  end
end
