# -*- coding: utf-8 -*-
require 'net/http'
require 'uri'
require 'json'

module AnmanAI
  module LLM
    class GeminiAdapter
      def initialize(config)
        @model = config.dig('llm', 'model') || "gemini-2.5-flash"
        @api_key = ENV['GEMINI_API_KEY'] || ENV['ANMAN_GEMINI_API_KEY'] || config.dig('llm', 'api_key')
        @base_url = config.dig('llm', 'base_url') || "https://generativelanguage.googleapis.com"
        
        if @api_key.nil? || @api_key.to_s.strip.empty? || @api_key == "ollama"
          raise "Gemini API Key is missing. Please set GEMINI_API_KEY in environment or config.yaml."
        end
      end

      def chat(system_prompt, user_prompt, temperature: 0.7, max_retries: 2)
        model_path = @model.include?('/') ? @model : "v1beta/models/#{@model}"
        target_url = "#{@base_url.sub(/\/+$/, '')}/#{model_path}:generateContent?key=#{@api_key}"
        uri = URI.parse(target_url)

        header = {
          'Content-Type' => 'application/json'
        }

        puts "[LLM DEBUG] Using Gemini native API: #{@base_url.sub(/\/+$/, '')}/#{model_path}:generateContent (key hidden)"
        puts "[LLM DEBUG] system_prompt length: #{system_prompt.length}, user_prompt length: #{user_prompt.length}"

        body = {
          contents: [
            {
              role: 'user',
              parts: [
                { text: user_prompt }
              ]
            }
          ],
          generationConfig: {
            temperature: temperature
          }
        }

        if system_prompt && !system_prompt.strip.empty?
          body[:systemInstruction] = {
            parts: [
              { text: system_prompt }
            ]
          }
        end

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
              content = data.dig('candidates', 0, 'content', 'parts', 0, 'text')
              if content.nil? || content.strip.empty?
                last_error = "Gemini returned empty response (attempt #{attempt + 1}/#{max_retries + 1})"
                STDERR.puts "[LLM Warning] #{last_error}"
                sleep 1
                next
              end
              return content
            elsif res.code == '429'
              last_error = "Gemini API Error 429 (Rate Limit): #{res.body[0..150]}"
              wait_sec = 6 * (attempt + 1)
              STDERR.puts "[LLM Warning] #{last_error}. Retrying in #{wait_sec} seconds..."
              sleep wait_sec
            else
              raise "Gemini API Error: #{res.code} - #{res.body[0..200]}"
            end
          rescue => e
            last_error = e.message
            STDERR.puts "[LLM Warning] Error on attempt #{attempt + 1}: #{e.message}"
            sleep 2
          end
        end

        raise "Gemini Client Error: #{last_error}"
      end
    end
  end
end
