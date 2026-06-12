#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'net/http'
require 'uri'
require 'pstore'
require 'json'
require 'time'

# CGIのロードパスを設定し、クラス定義を読み込む
CGI_DIR = File.expand_path('../public_html/aiwolf', __dir__)
$LOAD_PATH.unshift(CGI_DIR)

require 'util'
require 'player'
require 'vil'
require 'skill'
require 'charset'

PORT = 8063

class PlayerSession
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
    if res.code == '302' && res['set-cookie']
      @cookie = res['set-cookie'].split(';').first
      true
    else
      false
    end
  end

  def post(params)
    req = Net::HTTP::Post.new(@uri.path)
    req['Cookie'] = @cookie if @cookie
    req.set_form_data(params)
    Net::HTTP.start(@uri.host, @uri.port) { |http| http.request(req) }
  end

  def send_msg!(vid, text, options={})
    params = { 'cmd' => 'msg', 'message' => text, 'vid' => vid.to_s, 'j_data' => 'あ' }
    params.merge!(options)
    post(params)
  end

  # APIへCookie付きでGETリクエストを送信
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

puts "=== APIセキュリティ・情報閲覧制限テストを開始します ==="

# 1. 村のセットアップ
num_players = 16
users = (1..15).map { |i| PlayerSession.new("test_user#{i}", "pass#{i}") }
users.each do |u|
  u.login!
  sleep 0.1
end

creator = users.first
res = creator.post(
  'cmd' => 'mkvil', 'name' => 'test_api_sec_vil', 'sname' => 'apisec',
  'pass' => 'testpass', 'time' => '24', 'night_time' => '10', 'life_time' => '24',
  'entry_max' => num_players.to_s, 'entry_min' => num_players.to_s,
  'composition' => '1', 'dummy' => 'on', 'night_commit' => 'on'
)

global_db_path = File.join(CGI_DIR, 'db/vil.db')
vid = nil
PStore.new(global_db_path).transaction(true) { |db| vid = db['recent_vid'].to_i }
puts "村を作成しました。ID: #{vid}"

# 入村
users.each_with_index do |user, index|
  pid = index + 1
  user.post('cmd' => 'entry', 'vid' => vid.to_s, 'pid' => pid.to_s, 'pass' => 'testpass', 'message' => 'よろしくお願いします', 'j_data' => 'あ')
  sleep 0.1
end

sleep 0.5

# ゲーム開始
creator.post('cmd' => 'upstart', 'vid' => vid.to_s)

# DBの読み込み
db_path = File.join(CGI_DIR, "db/vil#{(vid - 1) / 100}/#{vid}.db")
db = PStore.new(db_path)

# 各種役割を持つプレイヤーの特定
werewolf_session = nil
seer_session = nil
villager_session = nil

db.transaction(true) do
  vil = db['root']
  vil.players.each do |userid, player|
    next if userid == 'DUMMY'
    session = users.find { |u| u.userid == userid }
    case player.sid
    when 1 # 人狼
      werewolf_session = session if werewolf_session.nil?
    when 2 # 占い師
      seer_session = session if seer_session.nil?
    when 0 # 村人
      villager_session = session if villager_session.nil?
    end
  end
end

puts "人狼プレイヤー: #{werewolf_session.userid}"
puts "占い師プレイヤー: #{seer_session.userid}"
puts "村人プレイヤー: #{villager_session.userid}"

errors = 0

# ----------------------------------------------------
# 検証 1: 独り言のマスキング検証（1日目昼）
# ----------------------------------------------------
puts "\n--- 検証 1: 独り言の閲覧制限検証 ---"
# 占い師が独り言を投稿
seer_session.send_msg!(vid, "私は本物の占い師です", 'think' => 'on')

# 1. 占い師（本人）がログAPIを叩く -> 独り言が見えるはず
res = seer_session.get_api('cmd' => 'log', 'vid' => vid.to_s, 'date' => '2')
if res.body.include?("私は本物の占い師です") && res.body.include?("(独り言)")
  puts "[OK] 占い師本人には自分の独り言が見えています。"
else
  puts "[ERROR] 占い師本人に自分の独り言が見えていません。"
  errors += 1
end

# 2. 村人（他人）がログAPIを叩く -> 独り言が見えないはず
res = villager_session.get_api('cmd' => 'log', 'vid' => vid.to_s, 'date' => '2')
if res.body.include?("私は本物の占い師です")
  puts "[ERROR] 他人の独り言が村人に漏洩しています。"
  errors += 1
else
  puts "[OK] 他人の独り言は村人からは非表示になっています。"
end

# 3. ログインしていない状態（セッションなし）でログAPIを叩く -> 独り言が見えないはず
guest = PlayerSession.new("guest", "pass") # login!しない
res = guest.get_api('cmd' => 'log', 'vid' => vid.to_s, 'date' => '2')
if res.body.include?("私は本物の占い師です")
  puts "[ERROR] 未ログインユーザーに独り言が漏洩しています。"
  errors += 1
else
  puts "[OK] 未ログインユーザーからは独り言は非表示になっています。"
end


# ----------------------------------------------------
# 検証 2: 参加者一覧での投票済みフラグ（1日目昼）
# ----------------------------------------------------
puts "\n--- 検証 2: 参加者一覧での投票済みフラグ検証 ---"
# 占い師が村人に投票する
target_pid = nil
current_date = nil
db.transaction(true) do
  vil = db['root']
  target_pid = vil.players[villager_session.userid].num_id
  current_date = vil.date
end
seer_session.post('cmd' => 'vote', 'vote_id' => target_pid.to_s, 'set_date' => current_date.to_s, 'vid' => vid.to_s)

# 参加者APIを取得
res = villager_session.get_api('cmd' => 'players', 'vid' => vid.to_s)
players_json = JSON.parse(res.body)

seer_api_data = players_json.find { |p| p['userid'] == seer_session.userid }
villager_api_data = players_json.find { |p| p['userid'] == villager_session.userid }

if seer_api_data['voted'] == true
  puts "[OK] 投票した占い師のvotedフラグがtrueになっています。"
else
  puts "[ERROR] 投票した占い師のvotedフラグがtrueになっていません。"
  errors += 1
end

if villager_api_data['voted'] == false
  puts "[OK] 未投票の村人のvotedフラグがfalseになっています。"
else
  puts "[ERROR] 未投票の村人のvotedフラグがfalseになっていません。"
  errors += 1
end


# ----------------------------------------------------
# 1日目の進行（夜フェーズへ遷移）
# ----------------------------------------------------
puts "\n--- 夜フェーズへ遷移させます ---"
# ダミーの投票
surviving_pids = []
db.transaction(true) { |d| surviving_pids = d['root'].players.values.select { |p| p.dead == 0 }.map(&:num_id) }
db.transaction do |d|
  v = d['root']
  dummy_player = v.players['DUMMY']
  if dummy_player && dummy_player.dead == 0
    targets = surviving_pids - [dummy_player.num_id]
    dummy_player.vote = targets.sample || dummy_player.num_id
    d['root'] = v
  end
end

# 他全員投票
users.each do |user|
  p_dead = 0
  p_vote = -1
  p_num_id = 0
  current_date = 0
  db.transaction(true) do |d|
    v = d['root']
    p = v.players[user.userid]
    if p
      p_dead = p.dead
      p_vote = p.vote
      p_num_id = p.num_id
    end
    current_date = v.date
  end

  if p_dead == 0 && p_vote == -1
    targets = surviving_pids - [p_num_id]
    user.post('cmd' => 'vote', 'vote_id' => (targets.sample || p_num_id).to_s, 'set_date' => current_date.to_s, 'vid' => vid.to_s)
  end
end

# 夜になったことを確認
current_date = 0
is_night = false
db.transaction(true) do |d|
  current_date = d['root'].date
  is_night = d['root'].night
end
puts "日付: #{current_date}日目, 夜: #{is_night}"


# ----------------------------------------------------
# 検証 3: 狼のささやきと遠吠えの検証（1日目夜）
# ----------------------------------------------------
puts "\n--- 検証 3: 狼のささやき/遠吠えの閲覧制限検証 ---"
# 人狼が夜ささやきを投稿
werewolf_session.send_msg!(vid, "今夜は占い師を噛みましょう", 'whisper' => 'on')

# 1. 人狼本人がログを叩く -> ささやきが見えるはず
res = werewolf_session.get_api('cmd' => 'log', 'vid' => vid.to_s, 'date' => '2')
if res.body.include?("今夜は占い師を噛みましょう") && res.body.include?("(ささやき)")
  puts "[OK] 人狼本人にはささやきが見えています。"
else
  puts "[ERROR] 人狼本人にささやきが見えていません。"
  errors += 1
end

# 2. 村人がログを叩く -> ささやき本文は見えず、「わおーん」にマスクされているはず
res = villager_session.get_api('cmd' => 'log', 'vid' => vid.to_s, 'date' => '2')
if res.body.include?("今夜は占い師を噛みましょう")
  puts "[ERROR] 人狼のささやき本文が村人に漏洩しています。"
  errors += 1
elsif res.body.include?("狼の遠吠え: わおーん")
  puts "[OK] 村人には「狼の遠吠え: わおーん」とマスクされて見えています。"
else
  puts "[ERROR] 村人にささやきも遠吠えも表示されていません。"
  errors += 1
end


# ----------------------------------------------------
# 検証 4: 占い師の能力結果の検証（2日目昼）
# ----------------------------------------------------
puts "\n--- 検証 4: 占い師の能力結果閲覧制限検証 ---"
# 夜のスキル（占い・襲撃・護衛など）を全員分実行して日付を進行させる
surviving_pids = []
skill_req_players = []
db.transaction(true) do
  surviving_pids = d['root'].players.values.select { |p| p.dead == 0 }.map(&:num_id) rescue []
  if surviving_pids.empty?
    # dbを再読み込み
    vil = db['root']
    surviving_pids = vil.players.values.select { |p| p.dead == 0 }.map(&:num_id)
    skill_req_players = vil.skill_pids
  end
end

skill_req_players.each do |player|
  next if player.userid == 'DUMMY'
  
  # 占い師(sid=2)の場合は指定された村人を占う
  if player.sid == 2
    target_pid = nil
    current_date = nil
    db.transaction(true) do |d|
      target_pid = d['root'].players[villager_session.userid].num_id
      current_date = d['root'].date
    end
  else
    # 他の役職（人狼や狩人）は自分以外の生存者をランダムに選択
    current_date = nil
    db.transaction(true) { |d| current_date = d['root'].date }
    if player.sid == 1 && current_date <= 3
      # 初日襲撃（ダミー襲撃期間）はダミー(ID: 1)のみ
      target_pid = 1
    else
      targets = surviving_pids - [player.num_id]
      target_pid = targets.sample
    end
  end

  user_session = users.find { |u| u.userid == player.userid }
  if user_session && target_pid
    user_session.post(
      'cmd' => 'skill',
      'target_id' => target_pid.to_s,
      'set_date' => current_date.to_s,
      'vid' => vid.to_s
    )
  end
end

# 進行状況確認 (日付が3日目に進んでいるはず)
sleep 1.0
db.transaction(true) do |d|
  current_date = d['root'].date
  is_night = d['root'].night
end
puts "日付: #{current_date}日目, 夜: #{is_night}"

# 1. 占い師がログAPIを叩く -> 自分の占い結果が見えるはず (3日目のログ)
res = seer_session.get_api('cmd' => 'log', 'vid' => vid.to_s, 'date' => '3')
# 占い結果のアナウンスが含まれているか (例: 「〜 は人間でした」または「〜 は人狼でした」)
if res.body.include?("人間のようです") || res.body.include?("人狼のようです")
  puts "[OK] 占い師には自分の占い結果が表示されています。"
else
  puts "[ERROR] 占い師に自分の占い結果が表示されていません。"
  errors += 1
end

# 2. 村人(非占い師)がログAPIを叩く -> 他人の占い結果が見えないはず
res = villager_session.get_api('cmd' => 'log', 'vid' => vid.to_s, 'date' => '3')
if res.body.include?("人間のようです") || res.body.include?("人狼のようです")
  puts "[ERROR] 他人の占い結果が村人に漏洩しています。"
  errors += 1
else
  puts "[OK] 他人の占い結果は村人には表示されていません。"
end


# ----------------------------------------------------
# 検証 5: 村一覧のフィルタリング検証
# ----------------------------------------------------
puts "\n--- 検証 5: 村一覧のフィルタリング検証 ---"
# 1. 進行中 (playing) の村一覧を取得 -> 今回作成した村 (vid) が含まれるはず
res = villager_session.get_api('cmd' => 'vils', 'state' => 'playing')
vils_json = JSON.parse(res.body)
if vils_json.any? { |v| v['vid'] == vid }
  puts "[OK] 進行中でフィルタした村一覧に、作成した村が含まれています。"
else
  puts "[ERROR] 進行中でフィルタした村一覧に、作成した村が含まれていません。"
  errors += 1
end

# 2. 募集中 (recruiting) の村一覧を取得 -> 今回作成した村 (vid) は含まれないはず
res = villager_session.get_api('cmd' => 'vils', 'state' => 'recruiting')
vils_json = JSON.parse(res.body)
if vils_json.any? { |v| v['vid'] == vid }
  puts "[ERROR] 募集中でフィルタした村一覧に、進行中の村が含まれてしまっています。"
  errors += 1
else
  puts "[OK] 募集中でフィルタした村一覧に、進行中の村は含まれていません。"
end


# ----------------------------------------------------
# 検証 6: チャットログの時間指定フィルタリング検証
# ----------------------------------------------------
puts "\n--- 検証 6: チャットログの時間指定フィルタリング検証 ---"
# 通常発言を投稿（時間指定前メッセージ）
villager_session.send_msg!(vid, "時間指定テストメッセージ（前）")

# 一度ログを取得して、投稿されたメッセージのタイムスタンプを取得し、それに1秒足した時刻をborder_timeとする
res_pre = villager_session.get_api('cmd' => 'log', 'vid' => vid.to_s, 'date' => '3')
time_match = res_pre.body.match(/\[(.*?)\] .*?: 時間指定テストメッセージ（前）/)
if time_match
  pre_time_str = time_match[1]
  border_time = (Time.parse(pre_time_str) + 1).strftime("%Y/%m/%d %H:%M:%S")
else
  border_time = Time.now.strftime("%Y/%m/%d %H:%M:%S")
end

sleep 2.0

# 二つ目のメッセージを投稿（時間指定後メッセージ）
villager_session.send_msg!(vid, "時間指定テストメッセージ（後）")

# 基準時刻以降のログを取得する
res = villager_session.get_api('cmd' => 'log', 'vid' => vid.to_s, 'date' => '3', 'since' => border_time)

if res.body.include?("時間指定テストメッセージ（後）") && !res.body.include?("時間指定テストメッセージ（前）")
  puts "[OK] 時間指定フィルタが正しく動作し、指定時刻以降のログのみが返却されました。"
else
  puts "[ERROR] 時間指定フィルタが正しく動作していません。"
  puts "  -> ログ内容:\n#{res.body}"
  errors += 1
end


# ----------------------------------------------------
# 検証 7: ロングポーリングによるリアルタイムイベント配信の検証
# ----------------------------------------------------
puts "\n--- 検証 7: ロングポーリングによるリアルタイムイベント配信の検証 ---"

# 最新のイベントIDを把握するために一度 events を取得する
res_init = villager_session.get_api('cmd' => 'events', 'vid' => vid.to_s, 'since' => '0')
init_events = JSON.parse(res_init.body)
latest_id = init_events.empty? ? 0 : init_events.last['id']

# 7-1. 非同期ロングポーリング待機中のイベント検知
poll_thread = Thread.new do
  # 最新IDを指定してロングポーリングを開始（次のイベントを待つ）
  villager_session.get_api('cmd' => 'events', 'vid' => vid.to_s, 'since' => latest_id.to_s)
end

# 少し待ってから、別セッション（人狼）で発言を投稿してイベントを発生させる
sleep 0.5
werewolf_session.send_msg!(vid, "イベントテスト用の通常発言")

# スレッドの終了を待つ（ロングポーリングがイベントを検知して即時に返るはず）
poll_res = poll_thread.value

events_after = JSON.parse(poll_res.body)
if events_after.any? { |e| e['content'] == "イベントテスト用の通常発言" }
  puts "[OK] ロングポーリング待機中に投稿されたイベントをリアルタイムに検知しました。"
else
  puts "[ERROR] ロングポーリング待機中にイベントを検知できませんでした。"
  puts "  -> 受信イベント: #{events_after.inspect}"
  errors += 1
end

# 7-2. 権限フィルタリングの検証（人狼のささやき）
latest_id = events_after.empty? ? latest_id : events_after.last['id']

# 人狼がささやきを投稿
werewolf_session.send_msg!(vid, "人狼用のささやきイベント", 'whisper' => 'on')

# 村人がイベントを取得（ささやきは見えないはず）
res_villager = villager_session.get_api('cmd' => 'events', 'vid' => vid.to_s, 'since' => latest_id.to_s)
events_villager = JSON.parse(res_villager.body)

# 人狼がイベントを取得（ささやきが見えるはず）
res_wolf = werewolf_session.get_api('cmd' => 'events', 'vid' => vid.to_s, 'since' => latest_id.to_s)
events_wolf = JSON.parse(res_wolf.body)

has_whisper_villager = events_villager.any? { |e| e['type_code'] == 'whisper' }
has_whisper_wolf = events_wolf.any? { |e| e['type_code'] == 'whisper' && e['content'] == "人狼用のささやきイベント" }

if !has_whisper_villager && has_whisper_wolf
  puts "[OK] イベント配信においても、人狼のささやきは適切に権限フィルタリングされています。"
else
  puts "[ERROR] イベントの権限フィルタリングに失敗しました。"
  puts "  -> 村人の受信イベント: #{events_villager.inspect}"
  puts "  -> 人狼の受信イベント: #{events_wolf.inspect}"
  errors += 1
end


puts "\n=== テスト終了 ==="
if errors == 0
  puts "【すべての検証項目に合格しました】"
  exit 0
else
  puts "【エラーが #{errors} 件発生しました】"
  exit 1
end
