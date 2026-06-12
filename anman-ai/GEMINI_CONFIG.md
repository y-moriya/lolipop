# anman-ai - Gemini API 設定ガイド

本ドキュメントでは、アンマンAI (`anman-ai`) クライアントで Google Gemini API を使用してゲームに参加するための設定手順について解説します。

---

## 1. Gemini API キーの取得

Gemini API を利用するには、事前に API キーを取得する必要があります。

1. [Google AI Studio](https://aistudio.google.com/) にアクセスします。
2. Google アカウントでログインし、**"Get API key"** をクリックして新規 API キーを生成します。
3. 生成された API キー（`AIzaSy...` から始まる文字列）をコピーします。

---

## 2. 構成ファイル (config.yaml) の編集

アンマンAIの構成ファイル `anman-ai/config/config.yaml`（またはテンプレートからコピーしたファイル）の `llm:` セクションに、コピーした API キーと利用するモデルなどの設定を記述します。

### 設定例
```yaml
llm:
  provider: "gemini"                      # プロバイダに "gemini" を指定します
  api_key: "YOUR_GEMINI_API_KEY"         # コピーした Gemini API キーを設定します
  model: "gemini-2.5-flash"              # 使用するモデルを指定します（例: gemini-2.5-flash, gemini-2.5-pro, gemini-3.5-flash 等）
  compact_prompt: true                   # トークン節約のためにサマリー+差分ログのみを送るコンパクトモードを有効 (推奨: true)
  talk_interval_reactive: 10             # 反応発言の最小間隔（秒）。他人の発言に即座に反応して喋りすぎるのを防ぎます
  talk_interval_active: 60               # 能動発言の最小間隔（秒）。誰も喋っていないときに自分から喋り出す間隔です
```

> [!TIP]
> **環境変数を使用した API キーの指定**
> API キーを `config.yaml` に直接書く代わりに、環境変数 `GEMINI_API_KEY` または `ANMAN_GEMINI_API_KEY` にキーを設定してクライアントを起動することもできます。この場合、`config.yaml` 内の `api_key` 指定は空にするか省略可能です。

---

## 3. 設定パラメータ詳細

| パラメータ | 型 | デフォルト値 | 説明 |
| :--- | :--- | :--- | :--- |
| `provider` | 文字列 | `"gemini"` | LLM APIの提供元。Google Gemini を使用する場合は `"gemini"` または `"google"` を指定します。 |
| `api_key` | 文字列 | （必須） | Gemini APIキー。環境変数経由での指定も可能です。 |
| `model` | 文字列 | `"gemini-2.5-flash"` | 呼び出すモデル名。コストパフォーマンスに優れる `"gemini-2.5-flash"` や、推論性能の高い `"gemini-2.5-pro"` などを指定できます。 |
| `compact_prompt` | 真偽値 | `true` | `true` の場合、過去の全ログを送る代わりに「要約情報」と「新着チャット差分のみ」をLLMに送信します。トークン消費の抑制と応答速度向上に極めて有効です。 |
| `talk_interval_reactive`| 整数 | `10` | 他人のチャット発言に対して即応するまでの最小待機間隔（秒）。LLMの応答が速い場合に会話を連投して喋りすぎる現象を防ぎます。 |
| `talk_interval_active` | 整数 | `60` | 場が静まり返っている（新着チャットがない）ときに、自ら発言を開始するまでの最小間隔（秒）。 |

---

## 4. エラー時のフォールバック設定 (llm_fallback)

メインで使用している Gemini API の接続エラーやレートリミット（429エラーなど）が発生した場合に備え、自動で切り替える代替 LLM（Ollama など）を定義できます。

```yaml
llm_fallback:
  provider: "ollama"
  api_key: "ollama"
  base_url: "http://localhost:11434"
  model: "gemma4"
  compact_prompt: true
```
メイン LLM でエラーが発生すると、自動的にこの代替 LLM アダプターにリクエストが切り替わります。
