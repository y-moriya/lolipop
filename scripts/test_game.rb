#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'net/http'
require 'uri'
require 'pstore'

# CGIのロードパスを設定し、クラス定義を読み込む
CGI_DIR = File.expand_path('../public_html/aiwolf', __dir__)
$LOAD_PATH.unshift(CGI_DIR)

# クラス定義をロード
require 'util'
require 'player'
require 'vil'
require 'skill'
require 'charset'

# テスト実行用のポート (検証用に8064に設定、のちに8063に修正)
PORT = 8063

# 文字コード変換用ヘルパー (EUC-JP -> UTF-8)
def to_utf8(str)
  return "" if !str
  # バイナリとして扱い、EUC-JPからUTF-8に安全に強制変換する
  str.dup.force_encoding('EUC-JP').encode('UTF-8', invalid: :replace, undef: :replace)
end

class PlayerSession
  attr_reader :userid, :cookie

  def initialize(userid, password)
    @userid = userid
    @password = password
    @cookie = nil
    @uri = URI.parse("http://localhost:#{PORT}/aiwolf/index.cgi")
  end

  # ログイン（存在しない場合は自動登録）して Cookie を保持
  def login!
    req = Net::HTTP::Post.new(@uri.path)
    req.set_form_data('cmd' => 'login', 'userid' => @userid, 'pass' => @password)
    
    res = Net::HTTP.start(@uri.host, @uri.port) do |http|
      http.request(req)
    end

    if res.code == '302' && res['set-cookie']
      @cookie = res['set-cookie'].split(';').first
      puts "[#{@userid}] ログイン成功 (Cookie: #{@cookie})"
      true
    else
      puts "[#{@userid}] ログイン失敗 (HTTP #{res.code})"
      false
    end
  end

  # アクションをPOST送信
  def post(params)
    req = Net::HTTP::Post.new(@uri.path)
    req['Cookie'] = @cookie if @cookie
    req.set_form_data(params)

    res = Net::HTTP.start(@uri.host, @uri.port) do |http|
      http.request(req)
    end
    res
  end

  # メッセージの送信
  def send_msg!(vid, text, options={})
    params = {
      'cmd' => 'msg',
      'message' => text,
      'vid' => vid.to_s,
      'j_data' => 'あ'
    }
    params.merge!(options)
    post(params)
  end
end

# 引数から参加人数を取得（デフォルト 16人）
num_players = 16
if ARGV[0]
  num_players = ARGV[0].to_i
  if num_players < 4
    puts "エラー: 人数は4人以上に指定してください（CATTLEが最小構成のため）。"
    exit 1
  end
end

puts "参加人数: #{num_players}名 (ダミー含む)"

# 実プレイヤー数 (ダミーが1名入るため、実プレイヤーは N - 1 名)
num_humans = num_players - 1

# 1. プレイヤーセッションの初期化とログイン
users = (1..num_humans).map do |i|
  PlayerSession.new("test_user#{i}", "pass#{i}")
end

puts "--- 1. ログイン/ユーザー登録 ---"
users.each(&:login!)

# 2. 村の作成
puts "\n--- 2. 村の作成 ---"
creator = users.first
res = creator.post(
  'cmd' => 'mkvil',
  'name' => 'test_auto_vil',
  'sname' => 'test',
  'pass' => 'testpass',
  'time' => '24',
  'night_time' => '10',
  'life_time' => '24',
  'entry_max' => num_players.to_s,
  'entry_min' => num_players.to_s,
  'composition' => '7', # RANDOM = 7 (ランダム)
  'dummy' => 'on',      # ダミーあり（MASTERが入る）
  'night_commit' => 'on'
)

if res.code != '302'
  puts "エラー: 村の作成リクエストが失敗しました (HTTP #{res.code})"
  exit 1
end

# PStore から最新の vid (recent_vid) を取得する
global_db_path = File.join(CGI_DIR, 'db/vil.db')
if !File.exist?(global_db_path)
  puts "エラー: global db/vil.db が存在しません。"
  exit 1
end

vid = nil
PStore.new(global_db_path).transaction(true) do |db|
  vid = db['recent_vid'].to_i
end

if !vid || vid == 0
  puts "エラー: 新しい村のIDを取得できませんでした。"
  exit 1
end

puts "村の作成に成功しました。村ID: #{vid}"

# 3. 入村 (Entry)
puts "\n--- 3. 入村 ---"
users.each_with_index do |user, index|
  pid = index + 1
  # EUC-JP での日本語文字列判定を助けるためのダミー文字を j_data に入れる
  res = user.post(
    'cmd' => 'entry',
    'vid' => vid.to_s,
    'pid' => pid.to_s,
    'pass' => 'testpass',
    'message' => 'よろしくお願いします！',
    'j_data' => 'あ'
  )
  if res.code == '302'
    puts "[#{user.userid}] キャラクターID: #{pid} で入村完了"
  else
    puts "[#{user.userid}] 入村失敗 (HTTP #{res.code})"
    # エラー理由を特定するために、レスポンスHTMLの一部（タイトルやエラー文）を表示する
    clean_body = to_utf8(res.body).gsub(/<[^>]+>/, ' ').strip.gsub(/\s+/, ' ')
    puts "  -&gt; エラー内容: #{clean_body[0..300]}"
  end
end

# 3.5 ゲーム開始前の発言
puts "\n--- 3.5 ゲーム開始前の発言 ---"
users.each do |user|
  res1 = user.send_msg!(vid, "よろしくお願いします！")
  res2 = user.send_msg!(vid, "緊張するな...", 'think' => 'on')
  puts "[#{user.userid}] 開始前発言を送信しました。(通常: HTTP #{res1.code}, 独り言: HTTP #{res2.code})"
end

# 4. ゲーム開始 (upstart)
puts "\n--- 4. ゲーム開始 ---"
res = creator.post(
  'cmd' => 'upstart',
  'vid' => vid.to_s
)
if res.code == '302'
  puts "ゲーム開始シグナルを送信しました。"
else
  puts "ゲーム開始シグナル送信失敗 (HTTP #{res.code})"
  clean_body = to_utf8(res.body).gsub(/<[^>]+>/, ' ').strip.gsub(/\s+/, ' ')
  puts "  -> エラー内容: #{clean_body[0..400]}"
end

# 5. ゲーム進行ループ (投票とアクションの自動化)
puts "\n--- 5. ゲーム自動進行ループ ---"
db_path = File.join(CGI_DIR, "db/vil#{(vid - 1) / 100}/#{vid}.db")
if !File.exist?(db_path)
  puts "エラー: データベースファイルが見つかりません。パス: #{db_path}"
  exit 1
end

db = PStore.new(db_path)

# ループの最大試行回数（無限ループ防止）
MAX_STEPS = 30
step_count = 0

loop do
  step_count += 1
  if step_count > MAX_STEPS
    puts "エラー: 最大ステップ数に達したため、テストを強制終了します。"
    exit 1
  end

  vil = nil
  db.transaction(true) do
    vil = db['root']
  end

  puts "\n========================================"
  puts "【第 #{step_count} ステップ】"
  puts "村名: #{to_utf8(vil.name)} (状態: #{vil.state})"
  puts "日付: #{vil.date}日目 (#{vil.night ? '夜' : '昼'})"
  puts "----------------------------------------"
  
  # プレイヤー一覧と状態表示
  survivors_count = 0
  werewolf_count = 0
  human_count = 0
  
  vil.players.each do |userid, player|
    role_name = to_utf8(Skill.skills[player.sid].name)
    status = player.dead == 0 ? "生存" : "死亡 (状態:#{player.dead})"
    puts "  - #{to_utf8(player.name)} (ユーザー: #{to_utf8(userid)}, 役職: #{role_name}, 状態: #{status}, num_id: #{player.num_id})"
    
    if player.dead == 0
      survivors_count += 1
      if player.sid == 1 # 人狼
        werewolf_count += 1
      else
        human_count += 1
      end
    end
  end
  puts "生存者数: #{survivors_count} (人狼: #{werewolf_count}, 人間: #{human_count})"
  puts "========================================"

  # ゲーム終了判定
  # state: 1 (進行中), 2 (市民勝利), 3 (人狼勝利)
  if vil.state == 2
    puts "【テスト成功】市民陣営の勝利でゲーム終了！"
    break
  elsif vil.state == 3
    puts "【テスト成功】人狼陣営の勝利でゲーム終了！"
    break
  elsif vil.state != 1
    puts "【テスト終了】想定外のゲーム状態: #{vil.state}"
    break
  end

  # アクションの実行
  if !vil.night
    # 昼の発言
    puts "-> 昼フェーズ：発言を送信します。"
    vil.players.each do |userid, player|
      next if userid == 'DUMMY'
      user_session = users.find { |u| u.userid == userid }
      next unless user_session
      
      if player.dead == 0
        res1 = user_session.send_msg!(vid, "今日も生き残るぞ！")
        res2 = user_session.send_msg!(vid, "誰が怪しいだろうか...", 'think' => 'on')
        puts "  - [#{userid}] が昼発言を送信しました。(通常: HTTP #{res1.code}, 独り言: HTTP #{res2.code})"
      else
        res = user_session.send_msg!(vid, "ううう、無念だ...", 'groan' => 'on')
        puts "  - [#{userid}] (死亡) が墓場発言を送信しました。(HTTP #{res.code})"
      end
    end

    # 昼フェーズ：投票
    puts "\n-> 昼フェーズ：投票を行います。"
    
    # 1. ダミープレイヤーの投票をPStoreで直接書き込む（CGIがダミーの投票を受け付けないため、人間が投票する前に書き込んでおく）
    surviving_pids = vil.players.values.select { |p| p.dead == 0 }.map(&:num_id)
    db.transaction do
      v = db['root']
      dummy_player = v.players['DUMMY']
      if dummy_player && dummy_player.dead == 0
        # 自分以外の生存者に投票
        targets = surviving_pids - [dummy_player.num_id]
        target_pid = targets.sample || dummy_player.num_id
        dummy_player.vote = target_pid
        db['root'] = v # 書き戻し
        target_name = to_utf8(v.player_p(target_pid).name)
        puts "  - [DUMMY] (PStore) が #{target_name} に投票しました。(直接書き込み)"
      end
    end

    # 2. 人間プレイヤーの投票をHTTPで送信
    human_players = vil.players.select { |uid, p| p.dead == 0 && uid != 'DUMMY' }
    
    human_players.each do |userid, player|
      # 自分以外の生存している誰かに投票
      targets = surviving_pids - [player.num_id]
      target_pid = targets.sample || player.num_id # 誰もいなければ自分
      
      user_session = users.find { |u| u.userid == userid }
      if user_session
        res = user_session.post(
          'cmd' => 'vote',
          'vote_id' => target_pid.to_s,
          'set_date' => vil.date.to_s,
          'vid' => vid.to_s
        )
        target_name = to_utf8(vil.player_p(target_pid).name)
        puts "  - [#{userid}] が #{target_name} に投票しました。(HTTP #{res.code})"
        if res.code != '302'
          clean_body = to_utf8(res.body).gsub(/<[^>]+>/, ' ').strip.gsub(/\s+/, ' ')
          puts "    -> エラー詳細: #{clean_body[0..300]}"
        end
      end
    end
    
    # 3. 全員の投票完了による自動進行を待ちます。
    puts "  - 全員の投票完了による自動進行を待ちます。"

    
  else
    # 夜の発言
    puts "-> 夜フェーズ：発言を送信します。"
    vil.players.each do |userid, player|
      next if userid == 'DUMMY'
      user_session = users.find { |u| u.userid == userid }
      next unless user_session
      
      if player.dead == 0
        if player.sid == 1 # 人狼
          res1 = user_session.send_msg!(vid, "今夜は誰を襲撃しようか？", 'whisper' => 'on')
          res2 = user_session.send_msg!(vid, "占いを騙るべきか...", 'think' => 'on')
          puts "  - [#{userid}] (人狼) が夜発言を送信しました。(ささやき: HTTP #{res1.code}, 独り言: HTTP #{res2.code})"
        else
          res = user_session.send_msg!(vid, "今夜襲撃されないといいが...", 'think' => 'on')
          role_name = to_utf8(Skill.skills[player.sid].name)
          puts "  - [#{userid}] (#{role_name}) が夜発言を送信しました。(独り言: HTTP #{res.code})"
        end
      else
        res = user_session.send_msg!(vid, "夜は静かだな...", 'think' => 'on')
        puts "  - [#{userid}] (死亡) が夜発言を送信しました。(独り言: HTTP #{res.code})"
      end
    end

    # 夜フェーズ：スキルアクション
    puts "\n-> 夜フェーズ：スキル（占い・襲撃・護衛など）を実行します。"

    # 今夜スキル入力が必要なプレイヤーのリスト
    skill_req_players = vil.skill_pids
    surviving_pids = vil.players.values.select { |p| p.dead == 0 }.map(&:num_id)

    skill_req_players.each do |player|
      # DUMMY はセッションを持たないのでスキップ
      next if player.userid == 'DUMMY'

      # ターゲットを選択。基本的には自分以外の生存者から選択。
      targets = surviving_pids - [player.num_id]
      target_pid = targets.sample

      if target_pid
        user_session = users.find { |u| u.userid == player.userid }
        if user_session
          params = {
            'cmd' => 'skill',
            'target_id' => target_pid.to_s,
            'set_date' => vil.date.to_s,
            'vid' => vid.to_s
          }

          # キューピッド (sid=12) の場合は target_id2 も送信する
          if player.sid == 12
            target_pid2 = (targets - [target_pid]).sample || target_pid
            params['target_id2'] = target_pid2.to_s
          end

          res = user_session.post(params)
          role_name = to_utf8(Skill.skills[player.sid].name)
          target_name = to_utf8(vil.player_p(target_pid).name)
          puts "  - [#{player.userid}] (#{role_name}) が #{target_name} を対象に選択しました。(HTTP #{res.code})"
          if res.code != '302'
            clean_body = to_utf8(res.body).gsub(/<[^>]+>/, ' ').strip.gsub(/\s+/, ' ')
            puts "    -> エラー詳細: #{clean_body[0..300]}"
          end
        end
      end
    end
    
    # super_commitは送信せず、全員のスキル送信による自動進行を待ちます
  end

  # フェーズ進行のために少し待つ
  sleep 0.5
end
