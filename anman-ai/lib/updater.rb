# -*- coding: utf-8 -*-
require 'net/http'
require 'uri'
require 'fileutils'
require 'yaml'

module AnmanAI
  class Updater
    SNAPSHOT_ZIP_URL = "https://github.com/y-moriya/lolipop/releases/download/snapshot/anman-ai-snapshot-windows.zip"

    def self.run(exe_dir, zip_url = nil)
      puts "=== starting self-update ==="
      
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
      puts "Downloading update package from: #{zip_url}"
      begin
        download_file(zip_url, zip_path)
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
        merge_configurations(extracted_config_dir, local_config_dir)
      end

      # 4. Trigger file replacement script and exit
      puts "Preparing update application script..."
      is_local_dev = AnmanAI::BUILD_TIME == "local development" && !defined?(Ocran) && !ENV['OCRAN_EXECUTABLE']
      if is_local_dev
        puts "[System] Local development environment detected: skipping physical file replacement to protect source code."
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

      puts "Update prepared successfully. Exiting to apply update..."
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

    def self.apply_update_windows(extracted_root, exe_dir, zip_filename)
      bat_path = File.join(exe_dir, 'apply_update.bat')
      bat_content = <<~BATCH
        @echo off
        echo ============================================
        echo  anman-ai Updater
        echo ============================================
        echo Waiting for old processes to release files...

        :: Wait 2 seconds for parent process to release file handles
        timeout /t 2 /nobreak > nul

        echo Copying update files...
        robocopy "#{extracted_root.gsub('/', '\\')}" "#{exe_dir.gsub('/', '\\')}" /E /XD "#{File.join(exe_dir, 'update_tmp').gsub('/', '\\')}" /R:30 /W:1 /NFL /NDL /NP /NJH /NJS
        if errorlevel 8 (
          echo.
          echo [Error] Update failed: Files could not be copied.
          echo Please close any running anman-ai instances and try again.
          pause
          exit /b 1
        )

        echo Cleaning up...
        rmdir /s /q "#{File.join(exe_dir, 'update_tmp').gsub('/', '\\')}"
        if exist "#{File.join(exe_dir, zip_filename).gsub('/', '\\')}" (
          del "#{File.join(exe_dir, zip_filename).gsub('/', '\\')}"
        )
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
      spawn("cmd.exe /c start \"\" \"#{bat_path_win}\"")
    end

    def self.apply_update_unix(extracted_root, exe_dir, zip_filename)
      sh_path = File.join(exe_dir, 'apply_update.sh')
      sh_content = <<~SHELL
        #!/bin/sh
        echo "Waiting for anman-ai process to exit..."
        sleep 2
        echo "Copying update files..."
        cp -R "#{extracted_root}"/* "#{exe_dir}"/
        echo "Cleaning up..."
        rm -rf "#{File.join(exe_dir, 'update_tmp')}"
        rm -f "#{File.join(exe_dir, zip_filename)}"
        echo "Update complete!"
        rm -- "$0"
      SHELL

      File.write(sh_path, sh_content)
      FileUtils.chmod(0755, sh_path)
      spawn(sh_path, out: File::NULL, err: File::NULL)
    end
  end
end
