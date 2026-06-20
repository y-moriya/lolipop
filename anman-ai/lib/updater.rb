# -*- coding: utf-8 -*-
require 'net/http'
require 'uri'
require 'fileutils'
require 'yaml'

module AnmanAI
  class Updater
    SNAPSHOT_ZIP_URL = "https://github.com/y-moriya/lolipop/releases/download/snapshot/anman-ai-snapshot-windows.zip"

    def self.log_info(exe_dir, msg)
      puts msg
      begin
        log_dir = File.join(exe_dir, 'log')
        FileUtils.mkdir_p(log_dir)
        log_file = File.join(log_dir, 'updater.log')
        File.open(log_file, 'a') do |f|
          f.puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"
        end
      rescue => e
        # Ignore logging errors to avoid blocking updates
      end
    end

    def self.run(exe_dir, zip_url = nil)
      log_info(exe_dir, "=== starting self-update ===")
      
      if zip_url.nil? || zip_url.to_s.strip.empty?
        config_path = File.join(exe_dir, 'config', 'config.yaml')
        config = YAML.load_file(config_path) rescue {}
        use_snapshot = config.dig('update', 'use_snapshot') == true
        
        if use_snapshot
          zip_url = SNAPSHOT_ZIP_URL
        else
          zip_url = get_latest_release_url || SNAPSHOT_ZIP_URL
        end
      end

      # Resolve filename from zip_url
      uri = URI.parse(zip_url) rescue nil
      filename = uri ? File.basename(uri.path) : 'anman-ai-update.zip'
      filename = 'anman-ai-update.zip' if filename.empty? || !filename.end_with?('.zip')

      zip_path = File.join(exe_dir, filename)
      tmp_dir = File.join(exe_dir, 'update_tmp')

      # 1. Download
      log_info(exe_dir, "Downloading update package from: #{zip_url}")
      begin
        download_file(zip_url, zip_path)
      rescue => e
        log_info(exe_dir, "[Error] Download failed: #{e.message}")
        return false
      end

      # 2. Extract
      log_info(exe_dir, "Extracting ZIP package...")
      begin
        FileUtils.rm_rf(tmp_dir)
        success = extract_zip(zip_path, tmp_dir)
        unless success
          log_info(exe_dir, "[Error] Extraction failed.")
          return false
        end
      rescue => e
        log_info(exe_dir, "[Error] Extraction failed with exception: #{e.message}")
        return false
      end

      # 3. Merge configurations
      log_info(exe_dir, "Merging configuration files...")
      extracted_root = tmp_dir
      children = Dir.glob(File.join(tmp_dir, '*')).select { |f| File.directory?(f) }
      if children.size == 1
        extracted_root = children.first
      else
        sub_root = File.join(tmp_dir, 'anman-ai-snapshot-windows')
        extracted_root = sub_root if Dir.exist?(sub_root)
      end

      extracted_config_dir = File.join(extracted_root, 'config')
      local_config_dir = File.join(exe_dir, 'config')

      if Dir.exist?(extracted_config_dir)
        merge_configurations(exe_dir, extracted_config_dir, local_config_dir)
      end

      # 4. Trigger file replacement script and exit
      log_info(exe_dir, "Preparing update application script...")
      is_local_dev = AnmanAI::BUILD_TIME == "local development" && !defined?(Ocran) && !ENV['OCRAN_EXECUTABLE']
      if is_local_dev
        log_info(exe_dir, "[System] Local development environment detected: skipping physical file replacement to protect source code.")
        # Clean up downloaded zip and extracted folder
        FileUtils.rm_rf(tmp_dir)
        FileUtils.rm_f(zip_path)
        return true
      end

      if Gem.win_platform?
        apply_update_windows(extracted_root, exe_dir, filename)
      else
        apply_update_unix(extracted_root, exe_dir, filename)
      end

      log_info(exe_dir, "Update prepared successfully. Exiting to apply update...")
      true
    end

    private

    def self.get_latest_release_url
      begin
        require 'json'
        uri = URI.parse("https://api.github.com/repos/y-moriya/lolipop/releases")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 10

        req = Net::HTTP::Get.new(uri.path)
        req['User-Agent'] = 'anman-ai-updater/1.0'
        res = http.request(req)
        if res.code == '200'
          releases = JSON.parse(res.body)
          stable_releases = releases.reject { |r| r['tag_name'] == 'snapshot' || r['draft'] == true || r['prerelease'] == true }
          latest_release = stable_releases.first
          if latest_release
            asset = latest_release['assets']&.find { |a| a['name'] =~ /anman-ai.*\.zip/ }
            return asset ? asset['browser_download_url'] : latest_release['zipball_url']
          end
        end
      rescue
        # fallback to nil
      end
      nil
    end

    def self.download_file(url, dest_path)
      current_url = url
      5.times do
        uri = URI.parse(current_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.open_timeout = 15
        http.read_timeout = 60

        path = uri.path
        path += "?#{uri.query}" if uri.query

        req = Net::HTTP::Get.new(path)
        req['User-Agent'] = 'anman-ai-updater/1.0'

        res = http.request(req)
        if res.is_a?(Net::HTTPRedirection)
          current_url = res['location']
          next
        elsif res.is_a?(Net::HTTPSuccess)
          File.binwrite(dest_path, res.body)
          return true
        else
          raise "HTTP status #{res.code} - #{res.message}"
        end
      end
      raise "Too many redirects"
    end

    def self.extract_zip(zip_path, dest_dir)
      FileUtils.mkdir_p(dest_dir)
      if Gem.win_platform?
        # Try PowerShell first, fallback to tar (native since Win10 17063)
        cmd = "powershell -NoProfile -ExecutionPolicy Bypass -Command \"Expand-Archive -Path '#{zip_path}' -DestinationPath '#{dest_dir}' -Force\""
        success = system(cmd)
        unless success
          cmd_tar = "tar -xf \"#{zip_path}\" -C \"#{dest_dir}\""
          success = system(cmd_tar)
        end
        success
      else
        system("unzip -o \"#{zip_path}\" -d \"#{dest_dir}\"")
      end
    end

    def self.deep_merge(target, source)
      target.merge(source) do |key, oldval, newval|
        if oldval.is_a?(Hash) && newval.is_a?(Hash)
          deep_merge(oldval, newval)
        else
          newval
        end
      end
    end

    def self.merge_configurations(exe_dir, extracted_config_dir, local_config_dir)
      FileUtils.mkdir_p(local_config_dir)
      Dir.glob(File.join(extracted_config_dir, "*.{yaml,yml}")).each do |new_config_path|
        filename = File.basename(new_config_path)
        local_config_path = File.join(local_config_dir, filename)

        if File.exist?(local_config_path)
          begin
            new_data = YAML.load_file(new_config_path) || {}
            local_data = YAML.load_file(local_config_path) || {}
            merged_data = deep_merge(new_data, local_data)
            File.write(local_config_path, YAML.dump(merged_data))
            log_info(exe_dir, "  -> Merged config: #{filename}")
          rescue => e
            log_info(exe_dir, "  -> [Warning] Failed to merge #{filename}: #{e.message}")
          end
        else
          FileUtils.cp(new_config_path, local_config_path)
          log_info(exe_dir, "  -> Installed new config template: #{filename}")
        end
      end
    end

    def self.apply_update_windows(extracted_root, exe_dir, zip_filename)
      bat_path = File.join(exe_dir, 'apply_update.bat')
      log_file = File.join(exe_dir, 'log', 'updater.log')
      bat_content = <<~BATCH
        @echo off
        set "LOG_FILE=#{log_file.gsub('/', '\\')}"

        echo ============================================ >> "%LOG_FILE%"
        echo  anman-ai Updater (Windows Script) >> "%LOG_FILE%"
        echo  Time: %date% %time% >> "%LOG_FILE%"
        echo ============================================ >> "%LOG_FILE%"
        echo Waiting for old processes to release files... >> "%LOG_FILE%"

        :: Wait 2 seconds for parent process to release file handles
        timeout /t 2 /nobreak > nul

        echo Copying update files... >> "%LOG_FILE%"
        robocopy "#{extracted_root.gsub('/', '\\')}" "#{exe_dir.gsub('/', '\\')}" /E /R:30 /W:1 /NFL /NDL /NP /NJH /NJS >> "%LOG_FILE%" 2>&1
        if errorlevel 8 goto copy_failed

        echo Cleaning up... >> "%LOG_FILE%"
        rmdir /s /q "#{File.join(exe_dir, 'update_tmp').gsub('/', '\\')}" >> "%LOG_FILE%" 2>&1
        if exist "#{File.join(exe_dir, zip_filename).gsub('/', '\\')}" (
          del "#{File.join(exe_dir, zip_filename).gsub('/', '\\')}" >> "%LOG_FILE%" 2>&1
        )
        
        echo Update complete! Restarting... >> "%LOG_FILE%"
        if exist "anman-ai.exe" goto start_exe
        if exist "start.bat" goto start_bat
        goto end_update

        :start_exe
        echo Restarting anman-ai.exe... >> "%LOG_FILE%"
        start "" "anman-ai.exe"
        goto end_update

        :start_bat
        echo Restarting start.bat... >> "%LOG_FILE%"
        start "" "start.bat"
        goto end_update

        :copy_failed
        echo. >> "%LOG_FILE%"
        echo [Error] Update failed: Files could not be copied. >> "%LOG_FILE%"
        echo Please close any running anman-ai instances and try again. >> "%LOG_FILE%"
        
        echo.
        echo =======================================================
        echo  [Error] Update failed!
        echo  Please check details in:
        echo  "%LOG_FILE%"
        echo =======================================================
        pause
        exit /b 1

        :end_update
        echo Update process finished successfully. >> "%LOG_FILE%"
        del "%~f0"
      BATCH

      # Ensure Windows style line endings (CRLF) and write as binary
      bat_content_crlf = bat_content.gsub("\n", "\r\n")
      bat_path_win = bat_path.gsub('/', '\\')
      File.binwrite(bat_path, bat_content_crlf)
      spawn("cmd.exe /c start \"\" \"#{bat_path_win}\"")
    end

    def self.apply_update_unix(extracted_root, exe_dir, zip_filename)
      sh_path = File.join(exe_dir, 'apply_update.sh')
      log_file = File.join(exe_dir, 'log', 'updater.log')
      sh_content = <<~SHELL
        #!/bin/sh
        LOG_FILE="#{log_file}"
        echo "============================================" >> "$LOG_FILE"
        echo " anman-ai Updater (UNIX Script)" >> "$LOG_FILE"
        echo " Time: \$(date)" >> "$LOG_FILE"
        echo "============================================" >> "$LOG_FILE"
        echo "Waiting for anman-ai process to exit..." >> "$LOG_FILE"
        sleep 2
        echo "Copying update files..." >> "$LOG_FILE"
        cp -R "#{extracted_root}"/* "#{exe_dir}"/ >> "$LOG_FILE" 2>&1
        echo "Cleaning up..." >> "$LOG_FILE"
        rm -rf "#{File.join(exe_dir, 'update_tmp')}" >> "$LOG_FILE" 2>&1
        rm -f "#{File.join(exe_dir, zip_filename)}" >> "$LOG_FILE" 2>&1
        echo "Update complete! Restarting..." >> "$LOG_FILE"
        rm -- "\$0"
      SHELL

      File.write(sh_path, sh_content)
      FileUtils.chmod(0755, sh_path)
      spawn(sh_path, out: File::NULL, err: File::NULL)
    end
  end
end
