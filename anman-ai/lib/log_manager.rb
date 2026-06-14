# -*- coding: utf-8 -*-
require 'logger'
require 'fileutils'

module AnmanAI
  class TeeStream
    def initialize(original, logger, severity)
      @original = original
      @logger = logger
      @severity = severity
      @buffer = ""
    end

    def write(string)
      @original.write(string)
      @buffer << string.to_s
      while (line = @buffer.slice!(/\A.*?\n/))
        # Remove trailing carriage returns and newlines for clean logging
        clean_line = line.chomp.gsub(/\r$/, '')
        @logger.log(@severity, clean_line)
      end
    end

    def <<(string)
      write(string)
      self
    end

    def flush
      @original.flush
    end

    def close
      @original.close
    end
    
    def tty?
      @original.tty?
    end
  end

  def self.setup_logger(exe_dir, config)
    max_size_mb = config.dig('log', 'max_size_mb') || 10
    keep_files = config.dig('log', 'keep_files') || 5
    
    log_dir = File.join(exe_dir, 'log')
    FileUtils.mkdir_p(log_dir)
    log_file = File.join(log_dir, 'anman-ai.log')

    # Logger initialization
    $logger = Logger.new(
      log_file,
      keep_files,
      max_size_mb * 1024 * 1024
    )
    
    $logger.formatter = proc do |severity, datetime, progname, msg|
      "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] [#{severity}] #{msg}\n"
    end

    # Redirect STDOUT and STDERR through TeeStream
    $stdout = TeeStream.new(STDOUT, $logger, Logger::INFO)
    $stderr = TeeStream.new(STDERR, $logger, Logger::WARN)
  end
end
