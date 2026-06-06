#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
# build_windows.rb - OCRAN EXE ビルドスクリプト
# Windows上で実行: ruby build/build_windows.rb

require 'fileutils'

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
