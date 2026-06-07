#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'net/http'
require 'uri'
require 'pstore'
require 'json'
require 'yaml'
require 'thread'

# 人狼CGIとanman-aiのロードパスを設定
$LOAD_PATH.unshift(File.expand_path('../public_html/aiwolf', __dir__))
$LOAD_PATH.unshift(File.expand_path('../anman-ai/lib', __dir__))

require 'util'
require 'player'
require 'vil'
require 'skill'
require 'client'

PORT = 8063

class TestSession
  attr_reader :userid, :cookie
  def initialize(userid, password)
    @userid = userid
    @password = password
    @cookie = nil
    @uri = URI.parse("http://localhost:#{PORT}/aiwolf/index.cgi")
  end

  def login!
    req = Net::HTTP::Post.new(@uri.path)
    req.set_form_data('cmd' => 'login', 'userid' => @userid, 'pass' => @password)
    res = Net::HTTP.start(@uri.host, @uri.port) { |http| http.request(req) }
    set_cookie_header = res['Set-Cookie']
    if set_cookie_header
      @cookie = set_cookie_header.split(';').first
    end
  end

  def post(params)
    req = Net::HTTP::Post.new(@uri.path)
    req['Cookie'] = @cookie if @cookie
    req.set_form_data(params)
    res = Net::HTTP.start(@uri.host, @uri.port) { |http| http.request(req) }
    puts "[DEBUG] POST cmd=#{params['cmd']} -> HTTP #{res.code}"
    if res.code != '200' && res.code != '302'
      puts "  -> Response body: #{res.body[0..300]}..."
    end
    res
  end
  
  def get_api(params)
    api_uri = URI.parse("http://localhost:#{PORT}/aiwolf/api.cgi")
    api_uri.query = URI.encode_www_form(params)
    req = Net::HTTP::Get.new(api_uri)
    req['Cookie'] = @cookie if @cookie
    res = Net::HTTP.start(api_uri.host, api_uri.port) { |http| http.request(req) }
    res.body.force_encoding('UTF-8') if res && res.body
    res
  end
end

puts "=== AI人狼クライアント 'anman-ai' 自律プレイ検証テスト ==="

# 1. データベースの初期化
puts "\n--- データベースの初期化 ---"
begin
  # 既存のテストファイルをクリア
  File.delete("public_html/aiwolf/db/user.db") if File.exist?("public_html/aiwolf/db/user.db")
  File.delete("public_html/aiwolf/db/vil.db") if File.exist?("public_html/aiwolf/db/vil.db")
  
  Dir.glob("public_html/aiwolf/db/log0/*").each { |f| File.delete(f) }
  Dir.glob("public_html/aiwolf/db/vil0/*").each { |f| File.delete(f) }
  
  puts "[OK] データベースとログディレクトリをクリアしました。"
rescue => e
  puts "初期化中のエラー: #{e.message}"
end

# 2. テスト用ユーザー作成
puts "\n--- ユーザー作成 & ログイン ---"
config = YAML.load_file('anman-ai/config/config.yaml')
ai_userid = config['user']['userid']
ai_password = config['user']['password']

user_configs = [
  { id: ai_userid, pass: ai_password },
  { id: 'villager1', pass: 'pass1' },
  { id: 'villager2', pass: 'pass2' },
  { id: 'werewolf1', pass: 'pass3' }
]

user_configs.each do |cfg|
  db = PStore.new('public_html/aiwolf/db/user.db')
  db.transaction do
    db[cfg[:id]] = {
      'pass' => cfg[:pass],
      'name' => cfg[:id],
      'mail' => "#{cfg[:id]}@example.com",
      'win' => 0,
      'lose' => 0,
      'drawn' => 0,
      'play' => 0,
      'point' => 0,
      'host' => '127.0.0.1',
      'last_play' => Time.now
    }
  end
  puts "ユーザー作成: #{cfg[:id]}"
end

# セッションの初期化とログイン
sessions = {}
user_configs.each do |cfg|
  sess = TestSession.new(cfg[:id], cfg[:pass])
  sess.login!
  sessions[cfg[:id]] = sess
end

# 3. 村の作成
puts "\n--- 村の作成 ---"
creator = sessions['villager1']
res = creator.post(
  'cmd' => 'mkvil',
  'name' => 'AI_Test_Village',
  'sname' => 'aitest',
  'pass' => 'vilpass',
  'comment' => 'AI自動テスト村です',
  'period' => '10',         # 昼の時間 (短め)
  'night_period' => '10',   # 夜の時間 (短め)
  'life_period' => '60',
  'entry_max' => '4',
  'entry_min' => '4',
  'dummy' => '0',
  'hope_skill' => '0',
  'card' => '0',
  'first_guard' => '0',
  'sayfull' => '0',
  'actfull' => '0',
  'night_commit' => '0',
  'open_vote' => '0',
  'open_id' => '0',
  'open_skill' => '0',
  'death_defeat' => '0',
  'composition' => '4人',
  'char' => '0'
)

vid = 1

# 各プレイヤーのエントリー
char_ids = [1, 2, 3, 4]
user_configs.each_with_index do |cfg, index|
  sess = sessions[cfg[:id]]
  sess.post(
    'cmd' => 'entry',
    'vid' => vid.to_s,
    'pid' => char_ids[index].to_s,
    'pass' => 'vilpass',
    'message' => 'よろしくお願いします',
    'j_data' => 'あ'
  )
  puts "エントリー完了: #{cfg[:id]} (キャラID: #{char_ids[index]})"
end

# 村の開始
creator.post('cmd' => 'upstart', 'vid' => vid.to_s)
puts "村を開始しました。ID: #{vid}"

# 役職情報を確認
db_path = "public_html/aiwolf/db/vil0/#{vid}.db"
ai_role = nil
ai_num_id = nil
ai_char_name = nil
db = PStore.new(db_path)
db.transaction(true) do
  vil = db['root']
  vil.players.each do |name, p|
    role_name = Skill.skills[p.sid].name
    puts "役職割り当て: #{name} - #{role_name} (ID: #{p.num_id})"
    if name == ai_userid
      ai_role = role_name
      ai_num_id = p.num_id
      ai_char_name = p.name
    end
  end
end

# 4. LLM接続確認 & モック差し替え (Ollamaが起動していない場合用)
puts "\n--- LLM API 接続検証 ---"
llm_config = YAML.load_file('anman-ai/config/config.yaml')
begin
  uri = URI.parse("#{llm_config['llm']['base_url']}/chat/completions")
  path = uri.path.empty? ? "/v1/chat/completions" : uri.path
  req = Net::HTTP::Post.new(path, { 'Content-Type' => 'application/json' })
  req.body = { model: llm_config['llm']['model'], messages: [{ role: 'user', content: 'hello' }] }.to_json
  
  res = Net::HTTP.start(uri.host, uri.port, read_timeout: 2, open_timeout: 2) { |http| http.request(req) }
  if res.code == '200'
    puts "[System] Ollama API is active. Test will run against the real LLM."
  else
    raise "Ollama responded with status: #{res.code}"
  end
rescue => e
  puts "[System] Ollama is inactive or unreachable: #{e.message}"
  puts "[System] Mocking LLMClient for local integration test stability."
  
  # 動的に LLMClient のメソッドをオーバーライド
  module AnmanAI
    class LLMClient
      def chat(system_prompt, user_prompt, temperature: 0.7)
        my_name = nil
        if user_prompt =~ /あなたのプレイヤー名:\s*(.*)/
          my_name = $1.strip
        elsif system_prompt =~ /あなたは人狼ゲームのキャラクター「(.*?)」/
          my_name = $1.strip
        end
        
        if user_prompt.include?("vote_target")
          puts "[Mock LLM] Vote action triggered"
          target = "werewolf1"
          if user_prompt =~ /生存プレイヤー:\s*(.*)/
            survivors = $1.split(/,\s*/).map(&:strip).reject(&:empty?)
            target = survivors.find { |s| s != my_name } || survivors.first || "werewolf1"
          end
          {
            "thought" => "怪しいと思われる #{target} に投票します。",
            "vote_target" => target
          }.to_json
        elsif user_prompt.include?("fortune_target") || (user_prompt.include?("占い師") && user_prompt.include?("夜フェーズ"))
          puts "[Mock LLM] Fortune action triggered"
          target = "werewolf1"
          if user_prompt =~ /生存プレイヤー:\s*(.*)/
            survivors = $1.split(/,\s*/).map(&:strip).reject(&:empty?)
            target = survivors.find { |s| s != my_name } || survivors.first || "werewolf1"
          end
          {
            "thought" => "怪しいと思われる #{target} を占います。",
            "fortune_target" => target
          }.to_json
        elsif user_prompt.start_with?("人狼ゲームの村のエントリー")
          puts "[Mock LLM] Entry greeting action triggered"
          "よろしくお願いします。"
        elsif user_prompt.start_with?("これまでの点呼・待機中チャット")
          puts "[Mock LLM] Recruitment chat action triggered"
          "ゲーム開始が楽しみですね！よろしくお願いします。"
        elsif user_prompt.start_with?("ゲームが終了しました。感想戦") || user_prompt.start_with?("これまでの感想戦チャット")
          puts "[Mock LLM] Epilogue greeting action triggered"
          "お疲れ様でした。楽しかったです！"
        else
          puts "[Mock LLM] Say action triggered"
          {
            "thought" => "冷静に状況を分析し、村への挨拶を投稿します。",
            "reasoning_update" => "他のプレイヤーが怪しいと感じています。",
            "message" => "こんにちは。村人の一人として、皆さんの発言や行動を注視しています。怪しい点があれば論理的に指摘していきます。"
          }.to_json
        end
      end
    end
  end
end

# 5. AIクライアントの別スレッド起動
puts "\n--- AIクライアント起動 ---"
ai_thread = Thread.new do
  begin
    ai_client = AnmanAI::Client.new('anman-ai/config/config.yaml', 'anman-ai')
    ai_client.instance_variable_set(:@vid, vid)
    ai_client.login!
    ai_client.init_game_state!
    ai_client.start_loop!
  rescue => e
    puts "[AI Thread Error] #{e.class}: #{e.message}"
  end
end

# クライアント初期化の時間を確保
sleep 2.0

# 6. 発言アクションの検証
puts "\n--- 6. 発言アクションの検証 ---"
sessions['villager1'].post('cmd' => 'msg', 'message' => '本日から人狼を推測していきましょう。', 'j_data' => 'a', 'vid' => vid.to_s)
puts "村人1が発言しました。AIがイベント検知して発言するのを待ちます..."

success_say = false
15.times do
  res = creator.get_api('cmd' => 'log', 'date' => '2', 'vid' => vid.to_s)
  if res && res.body.include?(ai_char_name)
    puts "[OK] AIプレイヤー '#{ai_char_name}' の発言がログに記録されました！"
    success_say = true
    break
  end
  sleep 1.0
end

unless success_say
  puts "[ERROR] AIプレイヤーが発言を行いませんでした。"
  
  log_path = "public_html/aiwolf/db/log0/1_2.html"
  if File.exist?(log_path)
    puts "  -> 1_1.html の中身:\n#{File.read(log_path)}"
  else
    puts "  -> 1_1.html は存在しません。"
  end
  
  db_path = "public_html/aiwolf/db/vil0/1.db"
  if File.exist?(db_path)
    db = PStore.new(db_path)
    db.transaction(true) do
      vil = db['root']
      if vil
        puts "  -> vil.events の数: #{vil.events.size}"
        vil.events.each { |ev| puts "     - #{ev.inspect}" }
      else
        puts "  -> vil が見つかりません。"
      end
    end
  else
    puts "  -> 1.db は存在しません。"
  end

  Thread.kill(ai_thread)
  exit 1
end

# 7. 投票アクションの検証
puts "\n--- 7. 投票アクションの検証 ---"
# 時間制限をオーバーさせて、夕方の投票フェーズへ強制移行させる
db.transaction do |d|
  d['root'].update_time = Time.now.to_i - 120
end
# CGIの進行を回すためダミーアクセス
creator.post('vid' => vid.to_s)

# 投票フェーズへ移行した直後に、自動投票時間切れを防ぐため update_time を未来にリセットする
db.transaction do |d|
  d['root'].update_time = Time.now.to_i + 120
end

# 投票フェーズへの移行待機と自動投票確認
success_vote = false
15.times do
  db.transaction(true) do |d|
    vil = d['root']
    ai_player = vil.players[ai_userid]
    if ai_player && ai_player.vote != -1
      puts "[OK] AIプレイヤーが投票を行いました！ (投票先ID: #{ai_player.vote})"
      success_vote = true
    end
  end
  break if success_vote
  sleep 1.0
end

unless success_vote
  puts "[ERROR] AIプレイヤーが投票を行いませんでした。"
  Thread.kill(ai_thread)
  exit 1
end

# 8. 夜アクション（占い）の検証（AIが占い師の場合）
if ai_role == "占い師"
  puts "\n--- 8. 夜フェーズの占いアクション検証 ---"
  
  # 自分（AI）が処刑されないよう、AI以外の生存プレイヤーのIDを1つ見つけてそこに投票を集中させる
  other_pid = nil
  db.transaction(true) do |d|
    other_pid = d['root'].players.values.find { |p| p.num_id != ai_num_id && p.dead == 0 }&.num_id
  end
  other_pid ||= (ai_num_id == 2 ? 3 : 2)

  # AI以外の他プレイヤー全員も投票を完了させ、夜フェーズへ移行させる
  user_configs.each do |cfg|
    next if cfg[:id] == ai_userid
    sess = sessions[cfg[:id]]
    sess.post('cmd' => 'vote', 'vote_id' => other_pid.to_s, 'set_date' => '2', 'vid' => vid.to_s)
  end
  
  # 夜フェーズへ移行した直後に、自動夜明けを防ぐため update_time を未来にリセットする
  db.transaction do |d|
    d['root'].update_time = Time.now.to_i + 120
  end

  # 占い実行の監視 (夜フェーズ中に設定されるのを待つ)
  success_fortune = false
  15.times do
    db.transaction(true) do |d|
      vil = d['root']
      ai_player = vil.players[ai_userid]
      if ai_player && ai_player.target && ai_player.target != -1
        puts "[OK] AI占い師が占い先を設定しました！ (占い先ID: #{ai_player.target})"
        success_fortune = true
      end
    end
    break if success_fortune
    sleep 1.0
  end
  
  unless success_fortune
    puts "[ERROR] AI占い師が占い能力を行使しませんでした。"
    Thread.kill(ai_thread)
    exit 1
  end

  # 締め切りのタイムアウトをトリガー
  db.transaction do |d|
    d['root'].update_time = Time.now.to_i - 120
  end
  creator.post('vid' => vid.to_s)

  # 朝フェーズへ移行した直後に、次の夕方への自動移行を防ぐため update_time を未来にリセットする
  db.transaction do |d|
    d['root'].update_time = Time.now.to_i + 120
  end
else
  puts "\n--- 8. 夜フェーズの占いアクション検証（AIが占い師ではないためスキップ） ---"
end

# AIスレッドの停止
Thread.kill(ai_thread)
puts "\n=== テスト完了: anman-ai の自律行動検証テストに合格しました ==="
exit 0
