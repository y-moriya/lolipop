# -*- coding: utf-8 -*-
require 'net/http'
require 'uri'
require 'fileutils'
require 'yaml'

module AnmanAI
  class Updater
    SNAPSHOT_ZIP_URL = "https://github.com/y-moriya/lolipop/releases/download/snapshot/anman-ai-snapshot-windows.zip"

    def self.run(exe_dir)
      puts "=== starting self-update ==="
      zip_path = File.join(exe_dir, 'anman-ai-snapshot-windows.zip')
      tmp_dir = File.join(exe_dir, 'update_tmp')

      # 1. Download
      puts "Downloading latest snapshot from: #{SNAPSHOT_ZIP_URL}"
      begin
        download_file(SNAPSHOT_ZIP_URL, zip_path)
      rescue => e
        puts "[Error] Download failed: #{e.message}"
        return false
      end

      # 2. Extract
      puts "Extracting ZIP package..."
      begin
        FileUtils.rm_rf(tmp_dir)
        success = extract_zip(zip_path, tmp_dir)
        unless success
          puts "[Error] Extraction failed."
          return false
        end
      rescue => e
        puts "[Error] Extraction failed with exception: #{e.message}"
        return false
      end

      # 3. Merge configurations
      puts "Merging configuration files..."
      extracted_root = File.join(tmp_dir, 'anman-ai-snapshot-windows')
      extracted_root = tmp_dir unless Dir.exist?(extracted_root)

      extracted_config_dir = File.join(extracted_root, 'config')
      local_config_dir = File.join(exe_dir, 'config')

      if Dir.exist?(extracted_config_dir)
        merge_configurations(extracted_config_dir, local_config_dir)
      end

      # 4. Trigger file replacement script and exit
      puts "Preparing update application script..."
      if Gem.win_platform?
        apply_update_windows(extracted_root, exe_dir)
      else
        apply_update_unix(extracted_root, exe_dir)
      end

      puts "Update prepared successfully. Exiting to apply update..."
      true
    end

    private

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

    def self.merge_configurations(extracted_config_dir, local_config_dir)
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
            puts "  -> Merged config: #{filename}"
          rescue => e
            puts "  -> [Warning] Failed to merge #{filename}: #{e.message}"
          end
        else
          FileUtils.cp(new_config_path, local_config_path)
          puts "  -> Installed new config template: #{filename}"
        end
      end
    end

    def self.apply_update_windows(extracted_root, exe_dir)
      bat_path = File.join(exe_dir, 'apply_update.bat')
      bat_content = <<~BATCH
        @echo off
        echo ============================================
        echo  anman-ai Updater
        echo ============================================
        echo Waiting for old processes to release files...

        set retry_count=0
        :copy_loop
        xcopy /y /e /s /i "#{extracted_root.gsub('/', '\\')}" "#{exe_dir.gsub('/', '\\')}" > nul 2>&1
        if errorlevel 1 (
          set /a retry_count+=1
          if %retry_count% gtr 30 (
            echo.
            echo [Error] Update failed: Files are locked by another process.
            echo Please close any running anman-ai instances and try again.
            pause
            exit /b 1
          )
          echo   Files are locked. Retrying... (%retry_count%/30)
          timeout /t 1 /nobreak > nul
          goto copy_loop
        )

        echo Cleaning up...
        rmdir /s /q "#{File.join(exe_dir, 'update_tmp').gsub('/', '\\')}"
        del "#{File.join(exe_dir, 'anman-ai-snapshot-windows.zip').gsub('/', '\\')}"
        echo Update complete! Restarting...
        if exist "anman-ai.exe" (
          start "" "anman-ai.exe"
        ) else if exist "start.bat" (
          start "" "start.bat"
        )
        del "%~f0"
      BATCH

      bat_path_win = bat_path.gsub('/', '\\')
      File.write(bat_path, bat_content)
      spawn("cmd.exe", "/c", "start \"\" \"#{bat_path_win}\"")
    end

    def self.apply_update_unix(extracted_root, exe_dir)
      sh_path = File.join(exe_dir, 'apply_update.sh')
      sh_content = <<~SHELL
        #!/bin/sh
        echo "Waiting for anman-ai process to exit..."
        sleep 2
        echo "Copying update files..."
        cp -R "#{extracted_root}"/* "#{exe_dir}"/
        echo "Cleaning up..."
        rm -rf "#{File.join(exe_dir, 'update_tmp')}"
        rm -f "#{File.join(exe_dir, 'anman-ai-snapshot-windows.zip')}"
        echo "Update complete!"
        rm -- "$0"
      SHELL

      File.write(sh_path, sh_content)
      FileUtils.chmod(0755, sh_path)
      spawn(sh_path, out: File::NULL, err: File::NULL)
    end
  end
end
