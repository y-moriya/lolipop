# -*- coding: utf-8 -*-
require 'net/http'
require 'uri'
require 'json'

module AnmanAI
  module LLM
    class OllamaAdapter
      def initialize(config)
        @base_url = config.dig('llm', 'base_url') || "http://localhost:11434"
        @model = config.dig('llm', 'model')
        @api_key = ENV['ANMAN_LLM_API_KEY'] || config.dig('llm', 'api_key')
      end

      def chat(system_prompt, user_prompt, temperature: 0.7, max_retries: 2)
        base_uri = URI.parse(@base_url)
        host = base_uri.host
        port = base_uri.port
        scheme = base_uri.scheme
        
        # Ollama's native /api/chat is sent to scheme://host:port/api/chat
        target_url = "#{scheme}://#{host}:#{port}/api/chat"
        uri = URI.parse(target_url)

        header = {
          'Content-Type'  => 'application/json'
        }
        header['Authorization'] = "Bearer #{@api_key}" if @api_key && !@api_key.empty?

        puts "[LLM DEBUG] Using Ollama native API: #{target_url}"
        puts "[LLM DEBUG] system_prompt length: #{system_prompt.length}, user_prompt length: #{user_prompt.length}"

        body = {
          model:       @model,
          messages:    [
            { role: 'system', content: system_prompt },
            { role: 'user',   content: user_prompt }
          ],
          stream:      false,
          options: {
            num_ctx:     8192,
            temperature: temperature
          }
        }

        req      = Net::HTTP::Post.new(uri.path, header)
        req.body = body.to_json
        use_ssl  = uri.scheme == 'https'

        last_error = nil
        (max_retries + 1).times do |attempt|
          begin
            res = Net::HTTP.start(uri.host, uri.port, use_ssl: use_ssl) do |http|
              http.read_timeout = 90
              http.open_timeout = 15  # Ollama cold-start timeout
              http.request(req)
            end

            if res.code == '200'
              data    = JSON.parse(res.body)
              content = data.dig('message', 'content')
              if content.nil? || content.strip.empty?
                last_error = "LLM returned empty response (attempt #{attempt + 1}/#{max_retries + 1})"
                STDERR.puts "[LLM Warning] #{last_error}"
                sleep 1
                next
              end
              return content
            elsif res.code == '429'
              last_error = "LLM API Error 429 (Rate Limit): #{res.body[0..150]}"
              wait_sec = 6 * (attempt + 1)
              STDERR.puts "[LLM Warning] #{last_error}. Retrying in #{wait_sec} seconds..."
              sleep wait_sec
            else
              raise "LLM API Error: #{res.code} - #{res.body[0..200]}"
            end
          rescue => e
            last_error = e.message
            raise "LLM Client Connection Error: #{e.message}" unless e.message.include?("empty response") || e.message.include?("429")
            sleep 2
          end
        end

        raise "LLM Client Error: #{last_error}"
      end
    end
  end
end
