# lolipop - aiwolf server and anman-ai client

lolipopはロリポップレンタルサーバーで動作可能なチャット型人狼ゲームCGI `AI天国` (`public_html/aiwolf`) と、そのCGIの出力をポーリングしてLLMと連携しながら自律的にゲームに参加するAIクライアント `アンマンAI` (`anman-ai`) を1つに束ねたモノレポです。どちらもRubyで実装されています。

ローカルでの動作検証のためDevContainer環境が用意されており、VSCodeで立ち上げるだけで `localhost:8063/aiwolf/index.cgi` で人狼サーバーにアクセスできます。

---

## 1. aiwolf (人狼サーバーCGI「AI天国」)

`public_html/aiwolf` ディレクトリには、ゲームの実行エンジンとなるCGIサーバーコードが配置されています。

### 主要ファイル構成
- **[index.cgi](file:///home/wellk/project/lolipop/public_html/aiwolf/index.cgi) / [index.rb](file:///home/wellk/project/lolipop/public_html/aiwolf/index.rb)**:
  人間がブラウザから人狼ゲームをプレイするためのメインエントリーポイントです。
- **[api.cgi](file:///home/wellk/project/lolipop/public_html/aiwolf/api.cgi) / [api.rb](file:///home/wellk/project/lolipop/public_html/aiwolf/api.rb)**:
  アンマンAIをはじめとするボットクライアントのためのJSON APIエントリーポイントです。
- **[vil.rb](file:///home/wellk/project/lolipop/public_html/aiwolf/vil.rb)**:
  人狼ゲームの進行状態、プレイヤー、日付進行、イベント記録、勝敗判定などのゲームロジックを一元管理する `Vil` クラスの定義です。
- **[player.rb](file:///home/wellk/project/lolipop/public_html/aiwolf/player.rb)**: プレイヤーの状態（生死、投票先、役職など）を保持するクラスです。
- **[skill.rb](file:///home/wellk/project/lolipop/public_html/aiwolf/skill.rb)**: 役職ごとの属性や定義を管理します。

### API仕様 (`api.rb`)
`cmd` パラメータに応じて以下のデータを JSON（一部テキスト）形式で提供します。

| コマンド (`cmd`) | 説明 |
| :--- | :--- |
| `vils` | 稼働中の村一覧と進行状況（日付、生存人数、昼/夜状態、募集中・進行中・決着等のステータス）を取得します。 |
| `players` | 指定した村（`vid`）の参加者一覧（名前、生死状態 `dead`、投票済みフラグ `voted`、夜行動済みフラグ `acted` など）を取得します。ゲーム終了後や本人である場合は役職（`role`）も取得可能です。 |
| `role` / `my_role` | ログイン中の自分自身の役職名を取得します。 |
| `log` | 指定した日、または全日程のチャットログテキストを整形して取得します。時間（`since`）でのフィルタリングに対応しています。 |
| `events` | ロングポーリング（最大15秒待機）を用いたイベントストリーム（発言、システム通知、時間変更など）を差分取得します。 |
| `vil` / `info` | 指定した村の基本情報および詳細進行ステータスを取得します。 |

#### セキュリティと情報制限
ゲーム進行中に役職外の秘匿情報がクライアントへ流出しないよう、`log` および `events` APIでは閲覧プレイヤーの生存・役職・陣営に基づいて、他人の「独り言」「ささやき（遠吠え含む）」「うめき」「霊言」などを非表示またはマスキングするフィルタ処理が行われます。
（例：非人狼陣営のプレイヤーには、人狼の遠吠えは発言者を `システム`、内容を `狼の遠吠え: わおーん` に置換して配信されます）

### 状態の永続化
ゲーム状態は `PStore` を使用し、村の全体インデックスを `db/vil.db` に、個別の村の詳細を `db/vil{i/100}/{i}.db` に保存・永続化しています。

---

## 2. anman-ai (アンマンAIクライアント)

`anman-ai` ディレクトリには、LLMと連携して自律的にゲームに参加するAIクライアントが配置されています。

### 主要ファイル構成
- **[anman-ai/bin/anman-ai](file:///home/wellk/project/lolipop/anman-ai/bin/anman-ai)**:
  AIクライアントのメインエントリーポイント。ログイン、自動エントリー、初期化、メインループの制御を行います。
- **[anman-ai/lib/client.rb](file:///home/wellk/project/lolipop/anman-ai/lib/client.rb)**:
  API連携、イベント監視、LLMへの問い合わせと意思決定、発言・投票・夜行動の実行担当する中核クラス `AnmanAI::Client` です。
- **[anman-ai/lib/game_state.rb](file:///home/wellk/project/lolipop/anman-ai/lib/game_state.rb)**:
  イベントを受け取り、プレイヤーの生死や昼夜などの最新状態を管理する `AnmanAI::GameState` クラスです。
- **[anman-ai/lib/llm_client.rb](file:///home/wellk/project/lolipop/anman-ai/lib/llm_client.rb)** と **[llm/](file:///home/wellk/project/lolipop/anman-ai/lib/llm)** ディレクトリ:
  各種LLMアダプター（`gemini_adapter.rb`, `openai_compat_adapter.rb`, `ollama_adapter.rb`）とそれらを管理するクライアントです。
- **[anman-ai/lib/prompt_manager.rb](file:///home/wellk/project/lolipop/anman-ai/lib/prompt_manager.rb)** と **[prompts/](file:///home/wellk/project/lolipop/anman-ai/prompts)** ディレクトリ:
  プロンプトの読み込みとプレースホルダ置換（陣営別の基本指針や、状況別のテンプレート）を処理します。
- **[anman-ai/config/config.yaml.example](file:///home/wellk/project/lolipop/anman-ai/config/config.yaml.example)**:
  CGIサーバーの接続先、ボットアカウント情報、使用するLLMプロバイダやパラメータを設定するテンプレートです。

### 動作ロジック（メインループとイベント監視）
[anman-ai/lib/client.rb](file:///home/wellk/project/lolipop/anman-ai/lib/client.rb) の監視ループ `start_loop!` は以下のように協調動作します。

```mermaid
sequenceDiagram
    autonumber
    actor LLM as LLM API (Gemini/OpenAI/Ollama)
    participant Client as anman-ai Client (Main Thread)
    participant Queue as Event Queue
    participant Server as lolipop CGI Server (api.cgi)
    participant Thread as Event Monitor (Background Thread)

    loop Every 1 second (Long Polling)
        Thread->>Server: cmd=events&since=ID
        Server-->>Thread: New Events JSON
        Thread->>Queue: Push Events
    end

    loop Main Loop
        Client->>Queue: Pull & Process Events
        Client->>Client: Update GameState

        rect rgb(240, 248, 255)
            note over Client: Every 3 seconds
            Client->>Server: cmd=vil
            Server-->>Client: Update Time & Status
        end

        alt Actively Speak (Triggered by new chats or intervals)
            Client->>LLM: Request next talk (State context + Chat history)
            LLM-->>Client: Speak Content (JSON)
            Client->>Server: cmd=say (or think/whisper/groan)
        else Vote Phase (Time limit approaching / Local Test)
            Client->>Server: cmd=players (Check if already voted)
            Client->>LLM: Request vote target (Decision context)
            LLM-->>Client: Vote Target (JSON)
            Client->>Server: cmd=vote (Execute target player id)
        else Night Phase (Night Actions available & Not dead)
            Client->>LLM: Request night action (Ability target selection)
            LLM-->>Client: Action Target (JSON)
            Client->>Server: cmd=action (Execute target player id)
        end
    end
```

1. **イベント受信スレッド**:
   バックグラウンドで `cmd=events` をロングポーリングし、取得した新着イベントを `Event Queue` に格納します。
2. **メイン制御スレッド**:
   - `Event Queue` からイベントを取り出して `GameState` に反映します。
   - 3秒ごとに村情報（`cmd=vil`）を取得し、日付進行や時間制限（残り秒数）を同期します。
   - 自身の生存状態と現在のフェーズに合わせてアクションを実行します。
     - **発言・思考発信 (`check_and_say`)**: 他プレイヤーの発言に反応（間隔2秒以上）または能動的発言（間隔30秒以上）としてLLMにコンテキストを送信し、生成した発言（または独り言）を投稿します。
     - **投票 (`trigger_vote`)**: 昼フェーズの残り時間が45秒以下（ローカルテスト環境時は即時）かつ未投票の際、LLMを介して投票先（`vote_target`）を決定し投票します。締め切り直前（残り7秒以下）の場合は、LLM応答待ちによる突然死を避けるため、生存者からランダムに決定して即時投票します (`trigger_quick_fallback_vote!`)。
     - **夜行動 (`trigger_night_action`)**: 占い、人狼襲撃、護衛などの役職アクションをLLMに問い合わせて実行します。
     - **感想戦 (`check_and_say_epilogue`)**: ゲーム終了後、他プレイヤーの発言に即応して感想戦を行います。
     - **ロビー雑談 (`check_and_say_recruiting`)**: ゲーム開始前の募集中フェーズにおいて雑談を行います。

### プロンプト最適化 (`compact_prompt`)
LLM呼び出し時に `compact_prompt: true` が有効な場合、チャットログの全量を送る代わりに、`GameState` が蓄積した重要イベントの要約（`game_summary`）と、前回呼び出し以降に受信した新着チャット差分（`incremental_chat_logs`）のみをLLMに送信します。これによりコンテキスト長の増大を防ぎ、APIの応答速度向上とコスト削減を図っています。

### LLM接続・フォールバック機能
- **複数プロバイダ対応**: `Gemini` ネイティブAPI（`systemInstruction` に対応）、`OpenAICompat`（OpenAI、DeepSeek、OpenRouterなど）、`Ollama` の3種類のアダプターが実装されています。
- **フォールバック機構**: メインLLMのAPIエラーやレートリミット（429）が発生した際、`llm_fallback` で指定された別のLLMプロバイダに自動で処理を移譲する回復設計になっています。
- **思考タグの除去**: DeepSeek-R1などの推論モデルが生成する `<think>...</think>` タグを自動で検知してトリミングし、ゲーム上のチャットに不要な推論テキストが混入するのを防ぎます。

### WebUIによる設定管理と複数LLMプリセット保持
- **統合型 `config.yaml`**: 各LLMの設定ファイルは個別に分けるのではなく、単一の `config.yaml` で管理するように一本化されました。
- **複数プロバイダのプリセット保持 (`llm_providers`)**:
  `config.yaml` 内の `llm_providers` セクションにおいて、Gemini、Ollama、OpenAI互換の3種類のプロバイダ設定を個別のプリセットとして同時に保持できます。
  WebUI上で「LLMプロバイダ」を切り替えた際、フロントエンドが現在のプロバイダの設定値を一時キャッシュ（マージ）し、選択されたプロバイダのプリセット値をロードして表示フォームに自動反映します。これによりUI上でシームレスにプロバイダを切り替え可能です。
- **プレースホルダー自動クリア**:
  新規セットアップ時に `config.yaml.example` から設定をロードする際、`your_username` や `your_password` などのテンプレート初期値を検出し、WebUI上の入力フィールドを自動で空文字にしてユーザーの入力ミスを防止する機構が実装されています。

### 自己アップデート機構 (Windows / UNIX)
- **Windows環境 (`apply_update.bat`)**:
  WebUIからのアップデート実行時、実行ファイル（`anman-ai.exe`等）のロック解放やコピー時のプロンプトによるハングアップを防ぐため、以下の設計が行われています。
  - 親プロセス終了待ちウェイトとして実行開始時に 2秒間待機 (`timeout /t 2`)。
  - `xcopy` に代わって `robocopy` コマンドを使用し、対話的なプロンプトによるハングを回避しつつ、一時ディレクトリ `update_tmp` を `/XD` オプションで除外してコピー競合を防止。
  - ファイルロック時の自動リトライ (`/R:30 /W:1`) と、終了コード（`errorlevel` 8以上）による正確な成否判定。
- **UNIX環境 (`apply_update.sh`)**:
  非同期のシェルスクリプトでファイルをコピーし、一時フォルダを削除して完了するシンプルなアップデートロジックが動作します。

### テスト環境におけるモックと安定化
- **テストモード (`ANMAN_TEST_MODE`)**:
  `test_anman_ai.rb` などのテストスクリプト実行時、環境変数 `ANMAN_TEST_MODE=true` がセットされている場合に、テスト専用のモック動作（ローカルの Ollama 通信時のエラー回避や PStore 役職変更モックなど）を有効にして、シナリオテストおよびライフサイクルテストを安定して実行できるようにしています。

---

## 3. 開発・検証用ユーティリティ

リポジトリルートには、開発や検証、ビルドを円滑に行うためのスクリプト群が配置されています。

- **[start_anman_ai.sh](file:///home/wellk/project/lolipop/start_anman_ai.sh) / [stop_anman_ai.sh](file:///home/wellk/project/lolipop/stop_anman_ai.sh) / [watch_anman_ai.sh](file:///home/wellk/project/lolipop/watch_anman_ai.sh)**:
  AIクライアントをバックグラウンド（自動再起動プロセス [anman-ai/bin/run_loop.sh](file:///home/wellk/project/lolipop/anman-ai/bin/run_loop.sh) 経由）で起動・停止、およびログ監視するためのスクリプトです。
- **[test_ai.sh](file:///home/wellk/project/lolipop/test_ai.sh) / [test_lifecycle.sh](file:///home/wellk/project/lolipop/test_lifecycle.sh) / [test_security.sh](file:///home/wellk/project/lolipop/test_security.sh)**:
  AIクライアントとサーバー間のシナリオテスト、点呼や決着などのライフサイクルテスト、および他陣営のささやき等の秘匿情報が漏洩していないかをチェックするセキュリティテストを実行するスクリプトです。
- **[build/build_windows.rb](file:///home/wellk/project/lolipop/build/build_windows.rb)**:
  Windows環境でスタンドアロンの実行ファイル（`dist/anman-ai.exe`）をビルドするためのスクリプトです。`ocran` パッケージングツールを用いて、コード、プロンプト、設定テンプレートを1つの実行ファイルにまとめます。ビルド時にGitのコミットハッシュやタグから [version.rb](file:///home/wellk/project/lolipop/anman-ai/lib/version.rb) を動的に生成します。

---

## 4. 開発環境の制約事項

- **Node.js / npm の管理**:
  Node.js や npm などのランタイム・パッケージ管理ツールは、**必ず [mise](https://mise.jdx.dev/) を使用してインストールおよび管理**してください。
  直接システムに node をインストールするのではなく、プロジェクトルートの `mise.toml` を通じてバージョン（例: `node@24`）を制御してください。

---

## 5. 設計規約・互換性維持ルール

### チャットログ保存用HTMLの互換性維持（後方互換性の厳守）
- 投稿メッセージ等のHTML構築ロジックである [vil.rb](file:///home/wellk/project/lolipop/public_html/aiwolf/vil.rb) の `say` メソッド等が生成・データベース（PStore）に保存する HTML 文字列フォーマット（`<!--typehead id--><table class="message">...`）は**絶対に書き換えないでください**。
- メッセージ形式を直接変更すると、永続化された過去の村ログの読み込み時や、[api.rb](file:///home/wellk/project/lolipop/public_html/aiwolf/api.rb) 等にあるログ解析用の正規表現、およびボットクライアントとの連携がすべて破損します。
- デザインやレイアウトの調整（レスポンシブ化など）が必要な場合は、保存データ構造を書き換えるのではなく、スタイルシート（`v2.css`）側で `table.message` に対するスタイルを記述して対応してください。

### CGIテンプレート（クラシック/V2）の分離
- `skel/` 配下のテンプレートファイル（`msg.html`、`skill*.html` など）を変更する場合は、クラシック版 `index.cgi` の動作を壊さないために元のファイルを直接変更せず、プレフィックスとして `v2_` を付加したファイル（例: `v2_msg.html`）を新しく追加してください。
- [v2.rb](file:///home/wellk/project/lolipop/public_html/aiwolf/v2.rb) の `erbrun` / `erbres` メソッドが自動的に `v2_` プレフィックスのファイルを優先してロードするよう設計されています。これにより、クラシック版 `index.cgi` の表示を完全に保護できます。
