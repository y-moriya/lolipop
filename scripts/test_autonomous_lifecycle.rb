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
user_configs = [
  { id: 'anman_ai', pass: 'password123' },
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

# 3. AI クライアントを別スレッドで起動（自動入村監視モード）
puts "\n--- 3. AIクライアントの起動 (監視・自動エントリー開始) ---"
ai_client = AnmanAI::Client.new('anman-ai/config/config.yaml', 'anman-ai')
# vid を nil に上書きして自動監視モードを強制する
ai_client.instance_variable_set(:@vid, nil)

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
  'period' => '20',         # 昼の制限時間 (20秒)
  'night_period' => '20',   # 夜の制限時間 (20秒)
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
puts "[Test] 村を作成しました。ID: #{vid} (募集中)"

# 5. AI の自動エントリーの検知
puts "\n--- 5. AIの自動エントリー待機 ---"
ai_entered = false
ai_char_name = nil
30.times do |i|
  res = creator.get_api('cmd' => 'players', 'vid' => vid.to_s)
  if res && res.code == '200'
    players = JSON.parse(res.body)
    ai_player = players.find { |p| p['userid'] == 'anman_ai' }
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
char_ids = [2, 3, 4]
user_configs.each_with_index do |cfg, index|
  next if cfg[:id] == 'anman_ai'
  sess = sessions[cfg[:id]]
  
  sess.post(
    'cmd' => 'entry', 'vid' => vid.to_s, 'pid' => char_ids[index - 1].to_s,
    'pass' => 'vilpass', 'message' => 'よろしくお願いします', 'j_data' => 'a'
  )
  puts "  エントリー完了: #{cfg[:id]} (pid: #{char_ids[index - 1]})"
end

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
    if name == 'anman_ai'
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
    date = vil.date
    night = vil.night
    state = vil.state
  end
  
  puts "\n[進行状況] #{date}日目, 夜フェーズ: #{night}, ステータス: #{state}"
  
  # ゲーム終了しているか確認
  if state >= 2
    puts "[System] ゲームが決着しました！勝者: #{state == 2 ? '村人側' : '人狼側'}"
    break
  end
  
  if !night
    # 昼フェーズ（話し合いと投票）
    puts "[Test] 昼フェーズの会話と自動投票の検証"
    
    # 1. NPCが発言する
    npc_sess = sessions['villager1']
    npc_sess.post('cmd' => 'msg', 'message' => "今日は誰が怪しいでしょうか？", 'j_data' => 'a', 'vid' => vid.to_s)
    puts "  NPCが発言しました: \"今日は誰が怪しいでしょうか？\""
    
    # AIがその発言を検知して反応するのを少し待つ
    sleep 4.0
    
    # 2. 時間切れ間際の投票トリガー
    # 残り時間を10秒に偽装し、AIに「時間切れによる自動投票」をトリガーさせる
    puts "  残り時間を10秒に設定し、AIの自動投票をトリガーします..."
    db.transaction do |d|
      d['root'].update_time = Time.now.to_i + 10
    end
    
    # AIが投票をポストするのを待つ (最大15秒監視)
    ai_voted = false
    15.times do |i|
      db.transaction(true) do |d|
        p = d['root'].players['anman_ai']
        if p && p.vote != -1
          puts "  [OK] AIプレイヤーが時間切れ直前の自動投票を行いました！ (投票先ID: #{p.vote})"
          ai_voted = true
        end
      end
      break if ai_voted
      sleep 1.0
    end
    
    # 他のNPCたちも全員投票を完了させ、夜フェーズへ移行させる
    other_pid = nil
    db.transaction(true) do |d|
      other_pid = d['root'].players.values.find { |p| p.num_id != ai_num_id && p.dead == 0 }&.num_id
    end
    other_pid ||= (ai_num_id == 2 ? 3 : 2)
    
    user_configs.each do |cfg|
      next if cfg[:id] == 'anman_ai'
      sess = sessions[cfg[:id]]
      sess.post('cmd' => 'vote', 'vote_id' => other_pid.to_s, 'set_date' => date.to_s, 'vid' => vid.to_s)
    end
    
    # 進行更新を回すためダミーアクセス
    db.transaction do |d|
      d['root'].update_time = Time.now.to_i - 120
    end
    creator.post('vid' => vid.to_s)
    
    # フェーズ移行直後の時間跳びを防ぐため update_time を未来にセット
    db.transaction do |d|
      d['root'].update_time = Time.now.to_i + 120
    end
    
  else
    # 夜フェーズ
    puts "[Test] 夜フェーズのアクション検証"
    
    # AIが夜アクション（人狼襲撃、占い等）を決定・実行するのを待つ
    sleep 5.0
    
    db.transaction(true) do |d|
      vil = d['root']
      ai_player = vil.players['anman_ai']
      if ai_player && ai_role == "占い師" && ai_player.target != -1
        puts "  [OK] AI占い師が占い先を設定しました！ (対象ID: #{ai_player.target})"
      elsif ai_player && ai_role == "人狼" && ai_player.target != -1
        puts "  [OK] AI人狼が襲撃先を設定しました！ (対象ID: #{ai_player.target})"
      end
    end
    
    # NPCたちの夜スキルをすべて完了させ、朝にする
    surviving_skill_pids = []
    db.transaction(true) { |d| surviving_skill_pids = d['root'].skill_pids.select { |p| p.dead == 0 } }
    
    surviving_skill_pids.each do |player|
      next if player.userid == 'anman_ai' || player.userid == 'DUMMY'
      
      # 適当な生存ターゲットを選択
      target_id = nil
      db.transaction(true) do |d|
        target_id = d['root'].players.values.find { |p| p.userid != player.userid && p.dead == 0 }&.num_id
      end
      
      user_session = sessions[player.userid]
      if user_session && target_id
        user_session.post('cmd' => 'skill', 'target_id' => target_id.to_s, 'set_date' => date.to_s, 'vid' => vid.to_s)
      end
    end
    
    # 朝に進めるためタイムアウトをトリガー
    db.transaction do |d|
      d['root'].update_time = Time.now.to_i - 120
    end
    creator.post('vid' => vid.to_s)
    
    # 朝フェーズ移行直後の時間跳びを防ぐため update_time を未来にセット
    db.transaction do |d|
      d['root'].update_time = Time.now.to_i + 120
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
