#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
# build_windows.rb - OCRAN EXE ビルドスクリプト
# Windows上で実行: ruby build/build_windows.rb

require 'fileutils'

# Generate version file dynamically from Git
git_commit = `git rev-parse --short HEAD`.strip rescue 'unknown'
git_tag = `git describe --tags --exact-match 2>/dev/null`.strip rescue nil
version_str = git_tag ? git_tag : "1.2.0-snapshot (#{git_commit})"
build_time = Time.now.strftime('%Y-%m-%d %H:%M:%S JST')

version_content = <<~RUBY
  # -*- coding: utf-8 -*-
  # Generated dynamically by build script. Do not commit.
  module AnmanAI
    VERSION = #{version_str.inspect}
    BUILD_TIME = #{build_time.inspect}
  end
RUBY

File.write('anman-ai/lib/version.rb', version_content)
puts "Generated version.rb with VERSION=#{version_str}, BUILD_TIME=#{build_time}"

entry_point = 'anman-ai/bin/anman-ai'
output_exe  = 'dist/anman-ai.exe'

# Ensure output directory exists
FileUtils.mkdir_p('dist')

# OCRAN Build Command
# --no-autoload: Prevent autoload scanning to avoid unnecessary dll packing
# --verbose: Print detailed build outputs
cmd = [
  'ocran',
  entry_point,
  'anman-ai/lib/**/*.rb',             # Include all Ruby libraries
  'anman-ai/prompts/**/*',            # Include werewolf prompts templates
  'anman-ai/config/personality.yaml', # Include default personality template
  '--output', output_exe,
  '--no-autoload',
  '--verbose'
].join(' ')

puts "Building: #{cmd}"
system(cmd) or abort('Build failed!')
puts "Done: #{output_exe}"
