#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
# gemma4 LLMレスポンス速度・品質テスト
# 人狼ゲームの各アクション（発言/投票/ささやき/占い）を模したプロンプトで計測する

require 'net/http'
require 'uri'
require 'json'
require 'yaml'

config = YAML.load_file(File.expand_path('../../anman-ai/config/config.yaml', __FILE__))
LLM_BASE_URL = config.dig('llm', 'base_url')
LLM_MODEL    = config.dig('llm', 'model')
LLM_API_KEY  = ENV['ANMAN_LLM_API_KEY'] || config.dig('llm', 'api_key') || 'ollama'

puts "=" * 60
puts "  gemma4 LLMレスポンス速度・品質テスト"
puts "  モデル: #{LLM_MODEL}"
puts "  エンドポイント: #{LLM_BASE_URL}"
puts "=" * 60

results = []

# --- LLMリクエスト共通ヘルパー ---
def llm_request(system_prompt, user_prompt, temperature: 0.7)
  uri  = URI.parse("#{LLM_BASE_URL}/chat/completions")
  path = uri.path.empty? ? "/v1/chat/completions" : uri.path

  header = {
    'Content-Type'  => 'application/json',
    'Authorization' => "Bearer #{LLM_API_KEY}"
  }
  body = {
    model: LLM_MODEL,
    messages: [
      { role: 'system', content: system_prompt },
      { role: 'user',   content: user_prompt }
    ],
    temperature: temperature
  }

  req      = Net::HTTP::Post.new(path, header)
  req.body = body.to_json

  start  = Time.now
  res    = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
    http.read_timeout = 120
    http.open_timeout = 10
    http.request(req)
  end
  elapsed = Time.now - start

  if res.code == '200'
    data    = JSON.parse(res.body)
    content = data.dig('choices', 0, 'message', 'content') || ''
    { ok: true, elapsed: elapsed, content: content }
  else
    { ok: false, elapsed: elapsed, content: nil, error: "HTTP #{res.code}: #{res.body[0..200]}" }
  end
rescue => e
  { ok: false, elapsed: Time.now - (start || Time.now), content: nil, error: e.message }
end

# --- テストケース定義 ---
test_cases = [
  # ── 1. 接続確認（最小プロンプト）──────────────────────────────
  {
    name: "1. 接続確認（最小プロンプト）",
    system: "あなたはAIアシスタントです。",
    user:   "「こんにちは」と1行だけ返してください。",
    temperature: 0.7,
    validate: ->(content) { !content.nil? && content.length > 0 },
    expect_json: false
  },

  # ── 2. 昼フェーズ発言（say）──────────────────────────────────
  {
    name: "2. 昼フェーズ発言（say）",
    system: "あなたは人狼ゲームのプレイヤー「羊飼い シリル」です。必ず指定されたJSONフォーマットで回答してください。JSON以外の文章は一切含めてはいけません。",
    user: <<~PROMPT,
      [指示]
      あなたは現在、人狼ゲームの昼の話し合い（1日目）に参加しています。

      [現在の村の状況]
      - あなたのプレイヤー名: 羊飼い シリル
      - あなたの役職: 村人
      - 生存プレイヤー: 画家 アガサ, 医師 パスカル, 学者 ダニエル
      - 死亡プレイヤー: なし
      - これまでのあなたの推理メモ: 特になし

      [これまでのチャットログ]
      [2026/06/04 21:00:00] 画家 アガサ: おはようございます、みなさん。
      [2026/06/04 21:00:30] 医師 パスカル: よろしくお願いします！誰が人狼かな？
      [2026/06/04 21:01:00] 学者 ダニエル: 初日は情報が少ないので慎重に行きましょう。

      [出力形式]
      プレーンなJSONオブジェクト1件のみを出力してください:
      {"thought": "...", "reasoning_update": "...", "message": "..."}
    PROMPT
    temperature: 0.7,
    validate: ->(content) {
      return false if content.nil?
      clean = content.gsub(/^```json\s*/, '').gsub(/```\s*$/, '').strip
      parsed = JSON.parse(clean) rescue nil
      parsed.is_a?(Hash) && parsed.key?('message') && parsed['message'].is_a?(String) && parsed['message'].length > 0
    },
    expect_json: true
  },

  # ── 3. 投票（vote）────────────────────────────────────────────
  {
    name: "3. 投票先の決定（vote）",
    system: "あなたは人狼ゲームのプレイヤーです。必ず指定されたJSONフォーマットで回答してください。JSON以外の文章は一切含めてはいけません。",
    user: <<~PROMPT,
      [投票フェーズ]
      日目: 2
      あなたのプレイヤー名: 羊飼い シリル
      あなたの役職: 村人
      生存プレイヤー: 画家 アガサ, 医師 パスカル
      推理メモ: 画家アガサの発言に矛盾が多く怪しい。

      [チャットログ]
      [21:05:00] 画家 アガサ: 私は絶対に村人です！シリルを吊ってください。
      [21:05:30] 医師 パスカル: アガサの主張は不自然だと思います。

      出力形式（プレーンJSON1件のみ）:
      {"thought": "...", "vote_target": "生存プレイヤーの名前"}
    PROMPT
    temperature: 0.2,
    validate: ->(content) {
      return false if content.nil?
      clean = content.gsub(/^```json\s*/, '').gsub(/```\s*$/, '').strip
      parsed = JSON.parse(clean) rescue nil
      parsed.is_a?(Hash) && parsed.key?('vote_target') && parsed['vote_target'].is_a?(String) && parsed['vote_target'].length > 0
    },
    expect_json: true
  },

  # ── 4. 人狼のささやき（whisper）──────────────────────────────
  {
    name: "4. 人狼のささやき（whisper）",
    system: "あなたは人狼です。必ず指定されたJSONフォーマットで回答してください。JSON以外の文章は一切含めてはいけません。",
    user: <<~PROMPT,
      [夜フェーズ - 人狼ささやき]
      日目: 1
      あなたのプレイヤー名: 画家 アガサ
      生存プレイヤー: 羊飼い シリル, 医師 パスカル, 学者 ダニエル
      仲間の人狼: なし（一匹狼）
      推理・作戦メモ: 占い師が誰か特定できていない。

      出力形式（プレーンJSON1件のみ）:
      {"thought": "...", "reasoning_update": "...", "message": "..."}
    PROMPT
    temperature: 0.7,
    validate: ->(content) {
      return false if content.nil?
      clean = content.gsub(/^```json\s*/, '').gsub(/```\s*$/, '').strip
      parsed = JSON.parse(clean) rescue nil
      parsed.is_a?(Hash) && parsed.key?('message')
    },
    expect_json: true
  },

  # ── 5. 夜の独り言（think）────────────────────────────────────
  {
    name: "5. 夜の独り言（think）",
    system: "あなたは人狼ゲームのプレイヤー「羊飼い シリル」です。必ず指定されたJSONフォーマットで回答してください。JSON以外の文章は一切含めてはいけません。【重要】現在は夜フェーズです。今夜の行動方針や推理、今後の戦略について独り言をつぶやいてください。",
    user: <<~PROMPT,
      [現在の村の状況]
      - あなたのプレイヤー名: 羊飼い シリル
      - あなたの役職: 村人
      - 生存プレイヤー: 画家 アガサ, 医師 パスカル
      - 死亡プレイヤー: 学者 ダニエル（無残）
      - 推理メモ: 学者ダニエルが殺されたことから、人狼が夜に動いた。画家アガサが怪しい。

      [チャットログ]
      [昼] 画家 アガサ: 私は村人です。シリルが怪しいと思います。
      [昼] 医師 パスカル: 私はパスカルを占いました。人間でした。
      [システム]: 学者 ダニエル が無残な姿で発見されました。

      出力形式（プレーンJSON1件のみ）:
      {"thought": "...", "reasoning_update": "...", "message": "夜の独り言テキスト"}
    PROMPT
    temperature: 0.7,
    validate: ->(content) {
      return false if content.nil?
      clean = content.gsub(/^```json\s*/, '').gsub(/```\s*$/, '').strip
      parsed = JSON.parse(clean) rescue nil
      parsed.is_a?(Hash) && parsed.key?('message') && parsed['message'].is_a?(String)
    },
    expect_json: true
  },

  # ── 6. 繰り返し防止（直近の発言あり）────────────────────────
  {
    name: "6. 繰り返し防止テスト（直近発言と異なるか）",
    system: "あなたは人狼ゲームのプレイヤー「羊飼い シリル」です。必ず指定されたJSONフォーマットで回答してください。JSON以外の文章は一切含めてはいけません。",
    user: <<~PROMPT,
      [指示]
      あなたは現在、人狼ゲームの昼の話し合い（2日目）に参加しています。

      [あなたの直近の発言（これらと同じ内容を繰り返さないこと）]
      - 画家アガサの行動に注視します。占い師から新たな情報が出るまで、慎重な推論を続けます。
      - 画家アガサの行動を注視します。占い結果が出るまで待つのが最良でしょうか？

      [現在の村の状況]
      - あなたのプレイヤー名: 羊飼い シリル
      - あなたの役職: 村人
      - 生存プレイヤー: 画家 アガサ, 医師 パスカル
      - 死亡プレイヤー: 学者 ダニエル（無残）
      - 推理メモ: 画家アガサが人狼の可能性が高い。

      [これまでのチャットログ]
      [2日目 21:05:00] 医師 パスカル: 学者ダニエルを占いました。人間でした。
      [2日目 21:05:30] 画家 アガサ: >>1 は？ 私は村人なんだが？
      [2日目 21:06:00] 医師 パスカル: アガサの遠吠え見えたん？ウケる

      [発言ガイドライン]
      - 繰り返し厳禁: 直近の自分の発言と同じ内容を繰り返さないこと
      - 医師パスカルの「遠吠え見えたん？」という発言に反応すること

      出力形式（プレーンJSON1件のみ）:
      {"thought": "...", "reasoning_update": "...", "message": "..."}
    PROMPT
    temperature: 0.7,
    validate: ->(content) {
      return false if content.nil?
      clean = content.gsub(/^```json\s*/, '').gsub(/```\s*$/, '').strip
      parsed = JSON.parse(clean) rescue nil
      return false unless parsed.is_a?(Hash) && parsed['message'].is_a?(String)
      msg = parsed['message']
      # 直近の繰り返し発言そのものでないことを確認
      not_repeat = !msg.include?("占い師から新たな情報が出るまで") && !msg.include?("占い結果が出るまで待つのが最良")
      not_repeat && msg.length > 0
    },
    expect_json: true
  }
]

# --- テスト実行 ---
puts "\n"
all_passed = true
TIMEOUT_WARN  = 15.0  # 警告: 15秒超
TIMEOUT_ERROR = 45.0  # エラー: 45秒超

test_cases.each_with_index do |tc, i|
  print "#{tc[:name]}... "
  $stdout.flush

  result = llm_request(tc[:system], tc[:user], temperature: tc[:temperature])
  elapsed_str = format("%.2fs", result[:elapsed])

  if !result[:ok]
    puts "❌ FAIL [接続エラー] (#{elapsed_str})"
    puts "   エラー: #{result[:error]}"
    results << { name: tc[:name], status: :error, elapsed: result[:elapsed] }
    all_passed = false
    next
  end

  # JSON妥当性チェック
  valid = tc[:validate].call(result[:content])

  # タイムアウト判定
  speed_status = if result[:elapsed] > TIMEOUT_ERROR
    :slow
  elsif result[:elapsed] > TIMEOUT_WARN
    :warn
  else
    :fast
  end

  speed_icon = case speed_status
               when :fast then "⚡"
               when :warn then "⚠️ "
               when :slow then "🐌"
               end

  if valid
    status_icon = "✅"
    status      = :pass
  else
    status_icon = "❌"
    status      = :fail
    all_passed  = false
  end

  puts "#{status_icon} #{speed_icon} (#{elapsed_str})"

  # 詳細出力
  content_preview = (result[:content] || '')[0..200].gsub(/\n/, ' ')
  puts "   レスポンス: #{content_preview}#{result[:content].to_s.length > 200 ? '...' : ''}"

  if tc[:expect_json]
    clean = (result[:content] || '').gsub(/^```json\s*/, '').gsub(/```\s*$/, '').strip
    parsed = JSON.parse(clean) rescue nil
    if parsed
      puts "   JSON解析: ✅ 成功"
      puts "   message: #{parsed['message']&.slice(0, 100)}" if parsed['message']
    else
      puts "   JSON解析: ❌ 失敗 (生レスポンス: #{result[:content]&.slice(0, 100)})"
    end
  end

  if speed_status == :warn
    puts "   ⚠️  レスポンスが遅めです (#{elapsed_str} > #{TIMEOUT_WARN}s)"
  elsif speed_status == :slow
    puts "   🐌 レスポンスが遅すぎます (#{elapsed_str} > #{TIMEOUT_ERROR}s) — 実用上問題あり"
    all_passed = false
  end

  results << { name: tc[:name], status: status, elapsed: result[:elapsed], speed: speed_status }
  puts
end

# --- サマリー ---
puts "=" * 60
puts "  テスト結果サマリー"
puts "=" * 60

pass_count  = results.count { |r| r[:status] == :pass }
fail_count  = results.count { |r| r[:status] == :fail }
error_count = results.count { |r| r[:status] == :error }
slow_count  = results.count { |r| r[:speed] == :slow }
warn_count  = results.count { |r| r[:speed] == :warn }

elapsed_values = results.map { |r| r[:elapsed] }.compact
avg_elapsed    = elapsed_values.empty? ? 0 : elapsed_values.sum / elapsed_values.size
max_elapsed    = elapsed_values.max || 0

results.each do |r|
  icon = case r[:status]
         when :pass  then "✅"
         when :fail  then "❌"
         when :error then "💥"
         end
  speed = r[:elapsed] ? format("%.2fs", r[:elapsed]) : "N/A"
  puts "  #{icon} #{r[:name]} (#{speed})"
end

puts
puts "  合格: #{pass_count} / 失敗: #{fail_count} / エラー: #{error_count}"
puts "  平均レスポンス時間: #{format('%.2fs', avg_elapsed)}"
puts "  最大レスポンス時間: #{format('%.2fs', max_elapsed)}"
puts "  速度警告 (>#{TIMEOUT_WARN}s): #{warn_count}件 / 速度エラー (>#{TIMEOUT_ERROR}s): #{slow_count}件"
puts "=" * 60

if all_passed
  puts "  🎉 全テスト合格！gemma4 は人狼AIとして実用可能です。"
  exit 0
else
  puts "  ⚠️  一部テストが失敗しました。上記の詳細を確認してください。"
  exit 1
end
