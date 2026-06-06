# -*- coding: utf-8 -*-
require 'net/http'
require 'uri'
require 'json'

module AnmanAI
  module LLM
    class OpenAICompatAdapter
      def initialize(config)
        @base_url = config.dig('llm', 'base_url') || "https://api.openai.com"
        @model = config.dig('llm', 'model') || "gpt-4o-mini"
        @api_key = ENV['ANMAN_LLM_API_KEY'] || config.dig('llm', 'api_key')
        @max_tokens = config.dig('llm', 'max_tokens')
      end

      def chat(system_prompt, user_prompt, temperature: 0.7, max_retries: 2)
        base_uri = URI.parse(@base_url)
        path = base_uri.path.to_s.sub(/\/+$/, '')

        # Build correct endpoint path
        if path.end_with?('/v1/chat/completions')
          # Already complete
        elsif path.end_with?('/chat/completions')
          # Do nothing
        elsif path.end_with?('/v1')
          path += '/chat/completions'
        else
          path += '/v1/chat/completions'
        end

        # Reconstruction of URI
        port_part = base_uri.port ? ":#{base_uri.port}" : ""
        # Handle cases where port is default for scheme to avoid unnecessary port formatting
        if (base_uri.scheme == 'http' && base_uri.port == 80) || (base_uri.scheme == 'https' && base_uri.port == 443)
          port_part = ""
        end

        target_url = "#{base_uri.scheme}://#{base_uri.host}#{port_part}#{path}"
        uri = URI.parse(target_url)

        header = {
          'Content-Type'  => 'application/json'
        }
        header['Authorization'] = "Bearer #{@api_key}" if @api_key && !@api_key.empty?

        puts "[LLM DEBUG] Using OpenAI-compatible API: #{target_url}"
        puts "[LLM DEBUG] system_prompt length: #{system_prompt.length}, user_prompt length: #{user_prompt.length}"

        body = {
          model:       @model,
          messages:    [
            { role: 'system', content: system_prompt },
            { role: 'user',   content: user_prompt }
          ],
          temperature: temperature
        }
        body[:max_tokens] = @max_tokens if @max_tokens

        req      = Net::HTTP::Post.new(uri.request_uri, header)
        req.body = body.to_json
        use_ssl  = uri.scheme == 'https'

        last_error = nil
        (max_retries + 1).times do |attempt|
          begin
            res = Net::HTTP.start(uri.host, uri.port, use_ssl: use_ssl) do |http|
              http.read_timeout = 90
              http.open_timeout = 15
              http.request(req)
            end

            if res.code == '200'
              data    = JSON.parse(res.body)
              content = data.dig('choices', 0, 'message', 'content')
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
end
