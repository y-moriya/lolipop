# -*- coding: utf-8 -*-
require 'cgi'
require 'json'
require 'pstore'
require 'util'
require 'player'
require 'vil'
require 'skill'
require 'charset'
require 'conf'

class Api
  def initialize
    @cgi = CGI.new(accept_charset: "UTF-8")
    @cmd = @cgi['cmd']
    @vid = @cgi['vid'].to_i
  end

  def run
    case @cmd
    when 'vils'
      handle_vils
    when 'players'
      handle_players
    when 'log'
      handle_log
    else
      print "Content-Type: application/json; charset=UTF-8\nStatus: 400 Bad Request\n\n"
      print JSON.generate({ 'error' => 'Invalid or missing cmd parameter' })
    end
  rescue => e
    print "Content-Type: text/plain; charset=UTF-8\nStatus: 500 Internal Server Error\n\n"
    print "Internal Server Error:\n"
    print "#{e.class}: #{e.message}\n"
    print e.backtrace.join("\n")
  end

  private

  # 1. 村一覧を JSON で取得
  def handle_vils
    vils = []
    vldb = PStore.new('db/vil.db')
    vldb.transaction(true) do
      if vldb.root?('recent_vid')
        recent_vid = vldb['recent_vid'].to_i
        1.upto(recent_vid) do |i|
          next unless vldb.root?("root#{i}")
          vild = vldb["root#{i}"]
          
          # 各村の進行状況（現在の日付や生存人数など）を詳細DBから取得
          detail_data = {}
          detail_db_path = "db/vil#{(i - 1) / 100}/#{i}.db"
          if File.exist?(detail_db_path)
            begin
              detail_db = PStore.new(detail_db_path)
              detail_db.transaction(true) do
                vil_obj = detail_db['root']
                if vil_obj
                  detail_data = {
                    'date' => vil_obj.date,
                    'night' => vil_obj.night,
                    'survivors' => vil_obj.players.values.count { |p| p.dead == 0 }
                  }
                end
              end
            rescue
              # 読み込み失敗時は無視
            end
          end

          vils << {
            'vid' => vild['vid'],
            'name' => vild['name'],
            'sname' => vild['sname'],
            'state' => vild['state'], # 0=募集中, 1=進行中, 2=市民勝利, 3=人狼勝利
            'player_num' => vild['player_num'],
            'composition' => vild['composition'],
            'dummy' => vild['dummy'],
            'date' => detail_data['date'] || 0,
            'night' => detail_data['night'] || false,
            'survivors' => detail_data['survivors'] || 0
          }
        end
      end
    end
    
    print "Content-Type: application/json; charset=UTF-8\n\n"
    print JSON.generate(vils)
  end

  # 2. 参加者一覧を JSON で取得
  def handle_players
    if @vid <= 0
      print "Content-Type: application/json; charset=UTF-8\nStatus: 400 Bad Request\n\n"
      print JSON.generate({ 'error' => 'Invalid or missing vid parameter' })
      return
    end

    db_path = "db/vil#{(@vid - 1) / 100}/#{@vid}.db"
    if !File.exist?(db_path)
      print "Content-Type: application/json; charset=UTF-8\nStatus: 404 Not Found\n\n"
      print JSON.generate({ 'error' => 'Village not found' })
      return
    end

    players_list = []
    db = PStore.new(db_path)
    db.transaction(true) do
      vil = db['root']
      if vil
        # ゲーム終了している場合は全員の役職を開示
        game_over = vil.state >= 2
        
        vil.players.each do |userid, player|
          role_name = nil
          if game_over
            role_name = Skill.skills[player.sid].name
          end

          players_list << {
            'userid' => userid,
            'name' => player.name,
            'dead' => player.dead, # 0=生存, 1=死亡, 2=無残, 3=処刑
            'role' => role_name,   # 進行中は null
            'num_id' => player.num_id
          }
        end
      end
    end

    print "Content-Type: application/json; charset=UTF-8\n\n"
    print JSON.generate(players_list)
  end

  # 3. チャットログをテキストで取得
  def handle_log
    if @vid <= 0
      print "Content-Type: text/plain; charset=UTF-8\nStatus: 400 Bad Request\n\n"
      print "Error: Invalid or missing vid parameter"
      return
    end

    date_param = @cgi['date']
    log_dir = "db/log#{(@vid - 1) / 100}"
    
    if !File.exist?(log_dir)
      print "Content-Type: text/plain; charset=UTF-8\nStatus: 404 Not Found\n\n"
      print "Error: Village logs not found"
      return
    end

    log_files = []
    if date_param && date_param != 'all'
      file_path = "#{log_dir}/#{@vid}_#{date_param.to_i}.html"
      log_files << [date_param.to_i, file_path] if File.exist?(file_path)
    else
      # すべての日付のログを昇順で取得
      Dir.glob("#{log_dir}/#{@vid}_*.html").each do |file|
        if file =~ /#{@vid}_(\d+)\.html$/
          log_files << [$1.to_i, file]
        end
      end
      log_files.sort_by! { |d, f| d }
    end

    if log_files.empty?
      print "Content-Type: text/plain; charset=UTF-8\nStatus: 404 Not Found\n\n"
      print "Error: Logs not found for specified date"
      return
    end

    print "Content-Type: text/plain; charset=UTF-8\n\n"

    log_files.each do |day, path|
      print "=== #{day}日目 ===\n"
      File.open(path, "r:utf-8") do |f|
        f.each_line do |line|
          line.strip!
          next if line.empty?

          # 1. 通常発言、独り言、ささやき、うめき等のテーブル形式
          if line =~ /^<!--(say|think|whisper|groan|fanatic|spirit)\d*-->\s*<table class="message">.*?target="_blank">(.*?)<\/a>.*?<span class="time">(.*?)<\/span>.*?<div class="mes_(say|think|whisper|groan|fanatic|spirit)_body1">(.*?)<\/div>.*?<\/table>/
            type_code = $1
            speaker = $2
            time_str = $3
            content_html = $5

            text_content = content_html.gsub(/<br\s*\/?>/i, "\n").gsub(/<[^>]+>/, '')
            text_content = text_content.gsub(/&lt;/, '<').gsub(/&gt;/, '>').gsub(/&amp;/, '&').gsub(/&quot;/, '"')

            type_label = case type_code
                         when 'think' then ' (独り言)'
                         when 'whisper' then ' (ささやき)'
                         when 'groan' then ' (うめき)'
                         when 'fanatic' then ' (狂信ささやき)'
                         when 'spirit' then ' (死者ささやき)'
                         else ''
                         end

            print "[#{time_str}] #{speaker}#{type_label}: #{text_content}\n"

          # 1b. 狼の遠吠え
          elsif line =~ /<table class="message">.*?<td colspan="2" class="howl">狼の遠吠え<\/td>.*?<div class="mes_whisper_body1">(.*?)<\/div>.*?<\/table>/
            content = $1
            print "[システム] 狼の遠吠え: #{content}\n"

          # 2. アナウンス（システムメッセージ）
          elsif line =~ /^<!--(?:say|think|whisper|groan|fanatic|spirit)?\d*-->\s*<div class="announce.*?">(.*?)<\/div>/
            content_html = $1
            text_content = content_html.gsub(/<br\s*\/?>/i, "\n").gsub(/<[^>]+>/, '')
            text_content = text_content.gsub(/&lt;/, '<').gsub(/&gt;/, '>').gsub(/&amp;/, '&').gsub(/&quot;/, '"')
            print "[システム]: #{text_content}\n"

          # 3. 時間アナウンスや進行ブロック
          elsif line =~ /<(?:div|span) class="(?:time_announce|alllog_announce)">(.*?)<\/(?:div|span)>/
            content_html = $1
            text_content = content_html.gsub(/<[^>]+>/, '').strip
            print "[進行]: #{text_content}\n"
          end
        end
      end
      print "\n"
    end
  end
end

if __FILE__ == $0
  Api.new.run
end
