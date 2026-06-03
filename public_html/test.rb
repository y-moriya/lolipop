#!/usr/local/bin/ruby3.4
# -*- coding: utf-8 -*-

require 'cgi'

cgi = CGI.new

# HTTPヘッダーを出力 (空行が自動で入る)
puts cgi.header("type" => "text/html", "charset" => "utf-8")

# HTMLコンテンツを出力
puts <<~HTML
  <!DOCTYPE html>
  <html lang="ja">
  <head>
      <meta charset="UTF-8">
      <title>Lolipop Ruby CGI Test</title>
      <style>
          body {
              font-family: 'Helvetica Neue', Arial, sans-serif;
              background-color: #f7f9fc;
              color: #333;
              display: flex;
              justify-content: center;
              align-items: center;
              height: 100vh;
              margin: 0;
          }
          .container {
              background-color: #fff;
              padding: 2.5rem;
              border-radius: 12px;
              box-shadow: 0 8px 30px rgba(0, 0, 0, 0.05);
              text-align: center;
              max-width: 480px;
              width: 100%;
          }
          h1 {
              color: #e83e8c;
              margin-bottom: 1.5rem;
              font-size: 1.8rem;
          }
          .info {
              background-color: #f1f3f5;
              padding: 1rem;
              border-radius: 8px;
              margin-bottom: 1.5rem;
              font-family: monospace;
              font-size: 0.95rem;
              text-align: left;
          }
          .badge {
              display: inline-block;
              padding: 0.25rem 0.75rem;
              background-color: #e83e8c;
              color: white;
              border-radius: 50px;
              font-size: 0.8rem;
              font-weight: bold;
          }
      </style>
  </head>
  <body>
      <div class="container">
          <span class="badge">Local Dev Environment</span>
          <h1>Lolipop Ruby CGI Test</h1>
          <div class="info">
              <strong>Ruby Version:</strong> #{RUBY_VERSION}<br>
              <strong>Platform:</strong> #{RUBY_PLATFORM}<br>
              <strong>Interpreter Path:</strong> #{Gem.ruby}<br>
              <strong>Execution Mode:</strong> CGI
          </div>
          <p style="color: #666; font-size: 0.9rem;">
              このスクリプトは <strong>#!/usr/local/bin/ruby3.4</strong> で動作しています。<br>
              ロリポップ！サーバーと同一のシバン表記で動作可能です。
          </p>
      </div>
  </body>
  </html>
HTML
