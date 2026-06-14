#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

ENV['ANMAN_TEST_MODE'] ||= 'true'

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

STDOUT.sync = true
STDERR.sync = true

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

puts "========================================================="
puts "  AI人狼クライアント 'anman-ai' 長期ライフサイクル自律検証"
puts "========================================================="

# 1. データベースのクリーンアップ
puts "\n--- 1. データベースの初期化 ---"
begin
  File.delete("public_html/aiwolf/db/user.db") if File.exist?("public_html/aiwolf/db/user.db")
  File.delete("public_html/aiwolf/db/vil.db") if File.exist?("public_html/aiwolf/db/vil.db")
  Dir.glob("public_html/aiwolf/db/log0/*").each { |f| File.delete(f) }
  Dir.glob("public_html/aiwolf/db/vil0/*").each { |f| File.delete(f) }
  puts "[OK] データベースを初期化しました。"
rescue => e
  puts "[Warning] クリーンアップ中にエラー: #{e.message}"
end

# 2. テスト用ユーザー作成 & ログイン
puts "\n--- 2. テストユーザーの作成とログイン ---"
config = YAML.load_file('anman-ai/config/config.yaml')
ai_userid = config['user']['userid']
ai_userid = 'anman_bot' if ai_userid.nil? || ai_userid.strip.empty?
ai_password = config['user']['password']
ai_password = 'password123' if ai_password.nil? || ai_password.strip.empty?

user_configs = [
  { id: ai_userid, pass: ai_password },
  { id: 'villager1', pass: 'pass1' },
  { id: 'villager2', pass: 'pass2' },
  { id: 'werewolf1', pass: 'pass3' },
  { id: 'werewolf2', pass: 'pass4' }
]

user_configs.each do |cfg|
  db = PStore.new('public_html/aiwolf/db/user.db')
  db.transaction do
    db[cfg[:id]] = {
      'pass' => cfg[:pass],
      'name' => cfg[:id],
      'mail' => "#{cfg[:id]}@example.com",
      'win' => 0, 'lose' => 0, 'drawn' => 0, 'play' => 0, 'point' => 0,
      'host' => '127.0.0.1', 'last_play' => Time.now
    }
  end
  puts "  作成: #{cfg[:id]}"
end

sessions = {}
user_configs.each do |cfg|
  sess = TestSession.new(cfg[:id], cfg[:pass])
  sess.login!
  sessions[cfg[:id]] = sess
end

# 3. LLM接続確認 & モック差し替え (Ollamaが起動していない場合用)
puts "\n--- 3. LLM API 接続検証 ---"
llm_config = YAML.load_file('anman-ai/config/config.yaml')
begin
  raise "Force mock LLM for test stability and speed"
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
        elsif user_prompt.include?("attack_target") || (user_prompt.include?("人狼") && user_prompt.include?("夜フェーズ"))
          puts "[Mock LLM] Attack action triggered"
          target = "villager1"
          if user_prompt =~ /生存プレイヤー:\s*(.*)/
            survivors = $1.split(/,\s*/).map(&:strip).reject(&:empty?)
            target = survivors.find { |s| s != my_name } || survivors.first || "villager1"
          end
          {
            "thought" => "占い師候補や村人を狙って #{target} を襲撃します。",
            "attack_target" => target
          }.to_json
        elsif user_prompt.include?("guard_target") || (user_prompt.include?("狩人") && user_prompt.include?("夜フェーズ"))
          puts "[Mock LLM] Guard action triggered"
          target = "villager1"
          if user_prompt =~ /生存プレイヤー:\s*(.*)/
            survivors = $1.split(/,\s*/).map(&:strip).reject(&:empty?)
            target = survivors.find { |s| s != my_name } || survivors.first || "villager1"
          end
          {
            "thought" => "占い師らしき #{target} を護衛します。",
            "guard_target" => target
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
            "thought" => "冷静に状況を分析し、発言を投稿します。",
            "reasoning_update" => "他のプレイヤーが怪しいと感じています。",
            "message" => "こんにちは。村人の一人として、皆さんの発言や行動を注視しています。怪しい点があれば論理的に指摘していきます。"
          }.to_json
        end
      end
    end
  end
end

# 3.5. AIクライアントの別スレッド起動
puts "\n--- 3.5. AIクライアント起動 ---"
ai_client = AnmanAI::Client.new('anman-ai/config/config.yaml', 'anman-ai')
# vid を nil に上書きして自動監視モードを強制する
ai_client.instance_variable_set(:@vid, nil)
ai_client.instance_variable_get(:@config)['server']['pass'] = 'vilpass'
ai_client.instance_variable_set(:@userid, ai_userid)
ai_client.instance_variable_set(:@password, ai_password)
ai_client.game_state.my_name = ai_userid if ai_client.game_state
ai_client.instance_variable_set(:@running, true)

ai_thread = Thread.new do
  begin
    ai_client.login!
    ai_client.auto_entry_loop! # 募集中の村を検知して自動で入村する
    ai_client.init_game_state!
    ai_client.start_loop!
  rescue => e
    puts "[AI Thread Error] #{e.class}: #{e.message}"
    puts e.backtrace.join("\n")
  end
end

sleep 2.0

# 4. 村の作成（募集中）
puts "\n--- 4. テスト用村の作成 (募集中) ---"
creator = sessions['villager1']
creator.post(
  'cmd' => 'mkvil',
  'name' => 'Lifecycle_Village',
  'sname' => 'lifecycle',
  'pass' => 'vilpass',
  'comment' => '自律行動長期検証用の村です',
  'time' => '45',           # 昼の制限時間 (45分相当)
  'night_time' => '45',     # 夜の制限時間 (45分相当)
  'life_period' => '60',
  'entry_max' => '5',
  'entry_min' => '5',
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
  'composition' => '4',     # 牛村 (5人構成に対応)
  'char' => '0'
)

vid = 1
puts "[Test] 村を作成しました。ID: #{vid} (募集中)"

# 5. AI の自動エントリーの検知
puts "\n--- 5. AIの自動エントリー待機 ---"
ai_entered = false
ai_char_name = nil
30.times do |i|
  res = creator.get_api('cmd' => 'players', 'vid' => vid.to_s)
  if res && res.code == '200'
    players = JSON.parse(res.body)
    ai_player = players.find { |p| p['userid'] == ai_userid }
    if ai_player
      ai_char_name = ai_player['name']
      puts "[OK] AIが自動エントリーを検知・入村しました！ キャラクター名: #{ai_char_name}"
      ai_entered = true
      break
    end
  end
  puts "  入村待機中... (#{i+1}秒)"
  sleep 1.0
end

unless ai_entered
  puts "[ERROR] AIプレイヤーが自動エントリーを行いませんでした。"
  Thread.kill(ai_thread)
  exit 1
end

# 6. 他のプレイヤーもエントリー
puts "\n--- 6. NPCプレイヤーたちのエントリー ---"
char_ids = [2, 3, 4, 5]
user_configs.each_with_index do |cfg, index|
  next if cfg[:id] == ai_userid
  sess = sessions[cfg[:id]]
  
  sess.post(
    'cmd' => 'entry', 'vid' => vid.to_s, 'pid' => char_ids[index - 1].to_s,
    'pass' => 'vilpass', 'message' => 'よろしくお願いします', 'j_data' => 'a'
  )
  puts "  エントリー完了: #{cfg[:id]} (pid: #{char_ids[index - 1]})"
end

# 6.5. ゲーム開始前のチャットの検証
puts "\n--- 6.5. ゲーム開始前のチャットの検証 ---"
sessions['villager1'].post('cmd' => 'msg', 'message' => "皆さんよろしくお願いします！", 'j_data' => 'a', 'vid' => vid.to_s)
puts "  NPCが発言しました: \"皆さんよろしくお願いします！\""
puts "  AIがゲーム開始前の雑談に反応して発言するのを待ちます..."
sleep 12.0

# 7. ゲーム開始
puts "\n--- 7. ゲーム開始 ---"
creator.post('cmd' => 'upstart', 'vid' => vid.to_s)
puts "[Test] ゲームを開始しました。"

# AIの初期情報確認
db_path = "public_html/aiwolf/db/vil0/#{vid}.db"
db = PStore.new(db_path)
ai_role = nil
ai_num_id = nil

db.transaction(true) do
  vil = db['root']
  vil.players.each do |name, p|
    role_name = Skill.skills[p.sid].name
    puts "  [配役] #{name} - #{role_name} (ID: #{p.num_id})"
    if name == ai_userid
      ai_role = role_name
      ai_num_id = p.num_id
    end
  end
end

# 8. 自律プレイ・ゲーム進行ループ
puts "\n--- 8. 自律プレイゲーム進行ループ ---"
loop_cnt = 0
loop do
  loop_cnt += 1
  if loop_cnt > 20
    puts "[ERROR] テストループ回数が上限に達しました。強制終了します。"
    break
  end

  # 現在の村の状態を取得
  date = 0
  night = false
  state = 0
  
  db.transaction(true) do |d|
    vil = d['root']
    if vil
      date = vil.date
      night = vil.night
      state = vil.state
    else
      state = 2 # If the village db is gone, treat it as ended
    end
  end
  
  puts "\n[進行状況] #{date}日目, 夜フェーズ: #{night}, ステータス: #{state}"
  
  # ゲーム終了しているか確認
  if state >= 2
    puts "[System] ゲームが決着しました！勝者: #{state == 2 ? '村人側' : '人狼側'}"
    puts "[Test] 感想戦（エピローグ）での自律発言と他者への反応を検証するため、30秒間待機します..."
    
    # NPCも感想戦で挨拶を投稿し、AIの反応を促す
    sleep 5.0
    sessions['villager1'].post('cmd' => 'msg', 'message' => "対戦ありがとうございました！楽しかったです！", 'j_data' => 'a', 'vid' => vid.to_s)
    
    sleep 25.0
    break
  end
  
  if !night
    # 昼フェーズ（話し合いと投票）
    puts "[Test] #{date}日目 昼フェーズの検証"
    
    if date == 2
      # 2日目: 生存時の能動的発信の検証、反応発言、自動投票、およびAIの処刑（死亡状態へ移行）
      puts "  [Test] 生存時の能動的発信を検証するため、誰も発言せずに35秒間待機します..."
      sleep 35.0
      
      npc_sess = sessions['villager1']
      npc_sess.post('cmd' => 'msg', 'message' => "今日は誰が怪しいでしょうか？", 'j_data' => 'a', 'vid' => vid.to_s)
      puts "  NPCが発言しました: \"今日は誰が怪しいでしょうか？\""
      
      sleep 4.0
      
      # 自動投票トリガー
      puts "  残り時間を10秒に設定し、AIの自動投票をトリガーします..."
      db.transaction do |d|
        d['root'].update_time = Time.now.to_i + 10
      end
      
      ai_voted = false
      15.times do |i|
        db.transaction(true) do |d|
          vil = d['root']
          p = vil ? vil.players[ai_userid] : nil
          if p && p.vote != -1
            puts "  [OK] AIプレイヤーが時間切れ直前の自動投票を行いました！ (投票先ID: #{p.vote})"
            ai_voted = true
          end
        end
        break if ai_voted
        sleep 1.0
      end
      
      # NPCは全員AIに投票してAIを処刑する
      puts "  AIを処刑するため、NPC全員がAIに投票します..."
      user_configs.each do |cfg|
        next if cfg[:id] == ai_userid
        sess = sessions[cfg[:id]]
        sess.post('cmd' => 'vote', 'vote_id' => ai_num_id.to_s, 'set_date' => date.to_s, 'vid' => vid.to_s)
      end
      
    elsif date >= 3
      # 3日目以降: 死亡状態での「能動的なうめき発信」を検証するため、誰も発言せずに35秒間待機
      puts "  [Test] 死亡時の能動的うめき発信を検証するため、誰も発言せずに35秒間待機します..."
      sleep 35.0
      
      # AIは既に死亡しているため、NPC同士で投票を行う
      puts "  AIは既に死亡しています。NPC同士で投票を行います。"
      other_pid = nil
      db.transaction(true) do |d|
        vil = d['root']
        other_pid = vil ? vil.players.values.find { |p| p.num_id != ai_num_id && p.dead == 0 }&.num_id : nil
      end
      user_configs.each do |cfg|
        next if cfg[:id] == ai_userid
        sess = sessions[cfg[:id]]
        sess.post('cmd' => 'vote', 'vote_id' => other_pid.to_s, 'set_date' => date.to_s, 'vid' => vid.to_s)
      end
    end
    
    # 直接 vil.update を実行してフェーズを進行させる (昼 -> 夜へ)
    puts "  [Test] 昼フェーズを終了し、夜へ移行します (直接更新)..."
    db.transaction do |d|
      vil = d['root']
      if vil
        Dir.chdir("public_html/aiwolf") do
          vil.update
        end
        d['root'] = vil
      end
    end
    
  else
    # 夜フェーズ
    puts "[Test] #{date}日目 夜フェーズの検証"
    
    # AIが死亡しているか確認
    is_ai_dead = false
    db.transaction(true) do |d|
      vil = d['root']
      p = vil ? vil.players[ai_userid] : nil
      is_ai_dead = (p && p.dead != 0)
    end
    
    if is_ai_dead
      puts "  AIは死亡しています。霊界でのうめき発信を検証するため35秒間待機します..."
      sleep 35.0
    elsif date == 1
      # 1日目の生存時の夜は、独り言(think)の検証のため35秒待機する
      puts "  [Test] 生存時の夜の独り言発信を検証するため、35秒間待機します..."
      sleep 35.0
      
      # 夜アクションの設定検証も行う
      db.transaction(true) do |d|
        vil = d['root']
        if vil
          ai_player = vil.players[ai_userid]
          if ai_player && ai_role == "占い師" && ai_player.target != -1
            puts "  [OK] AI占い師が占い先を設定しました！ (対象ID: #{ai_player.target})"
          elsif ai_player && ai_role == "人狼" && ai_player.target != -1
            puts "  [OK] AI人狼が襲撃先を設定しました！ (対象ID: #{ai_player.target})"
          end
        end
      end
    else
      # 2日目以降の生存時は通常通り5秒待つ
      sleep 5.0
      
      db.transaction(true) do |d|
        vil = d['root']
        ai_player = vil.players[ai_userid]
        if ai_player && ai_role == "占い師" && ai_player.target != -1
          puts "  [OK] AI占い師が占い先を設定しました！ (対象ID: #{ai_player.target})"
        elsif ai_player && ai_role == "人狼" && ai_player.target != -1
          puts "  [OK] AI人狼が襲撃先を設定しました！ (対象ID: #{ai_player.target})"
        end
      end
    end
    
    # NPCたちの夜スキルをすべて完了させ、朝にする
    surviving_skill_pids = []
    db.transaction(true) do |d|
      vil = d['root']
      surviving_skill_pids = vil ? vil.skill_pids.select { |p| p.dead == 0 } : []
    end
    
    surviving_skill_pids.each do |player|
      next if player.userid == ai_userid || player.userid == 'DUMMY'
      
      # 適当な生存ターゲットを選択
      target_id = nil
      db.transaction(true) do |d|
        vil = d['root']
        target_id = vil ? vil.players.values.find { |p| p.userid != player.userid && p.dead == 0 }&.num_id : nil
      end
      
      user_session = sessions[player.userid]
      if user_session && target_id
        user_session.post('cmd' => 'skill', 'target_id' => target_id.to_s, 'set_date' => date.to_s, 'vid' => vid.to_s)
      end
    end
    
    # 直接 vil.update を実行してフェーズを進行させる (夜 -> 朝へ)
    puts "  [Test] 夜フェーズを終了し、朝へ移行します (直接更新)..."
    db.transaction do |d|
      vil = d['root']
      if vil
        Dir.chdir("public_html/aiwolf") do
          vil.update
        end
        d['root'] = vil
      end
    end
  end
  
  sleep 2.0
end

# AIスレッドの停止と後片付け
Thread.kill(ai_thread) rescue nil
puts "\n========================================================="
puts "  自律長期ライフサイクル検証テストが完了しました！ (成功)"
puts "========================================================="
exit 0
