# llm-wiki

LLM が構築・維持・参照する、永続的・累積的なグラフ構造のナレッジベースを Claude Code に与えるプラグイン。

## コンセプト

一般的な RAG は問い合わせのたびに知識をゼロから再発見する。本プラグインは違うアプローチを取る ——
LLM がソースを取り込むたびに、要点を抽出して **既存の Wiki に統合**し、相互リンク・要約・矛盾の注記を維持する。
知識は一度コンパイルされ、その後は **最新に保たれる**。Wiki は問い合わせや取り込みのたびに豊かになる、累積する成果物になる。

- あなたの仕事 — ソースの収集、探索、良い問いを投げること
- LLM の仕事 — 要約・相互参照・分類・整合性維持といった、人間が続けられない地道な保守

導入するだけで、Claude Code は暗黙的に Wiki を参照し、明示コマンドで取り込み・整理・再編できるようになる。

## インストール

Claude Code 内で以下を実行する:

```
/plugin marketplace add roamer7038/llm-wiki-plugin
/plugin install llm-wiki
```

フック設定の反映には Claude Code の再起動が必要。

## セットアップ

```
/wiki-init
```

`~/.llm-wiki/`（既定。環境変数 `LLM_WIKI_HOME` で上書き可）に構造とデフォルト設定を生成する。
続けてトピックを追加する:

```
/wiki-topic add rust Rust言語の学習・実践知識
```

## 操作（スキル）

各操作はスキルとして提供され、`/wiki-*` で明示的に呼び出せるほか、関連する依頼で自動的にトリガーされる。

| スキル | 説明 |
|--------|------|
| `/wiki-init` | Wiki を初期化する |
| `/wiki-ingest <path-or-url> [topic]` | ソースを取り込み、要約ページ・関連ページ・index/log を更新（確認付き） |
| `/wiki-query <question>` | Wiki を参照し、出典付きで回答。良い回答は還元可 |
| `/wiki-lint [scope]` | 健全性チェック（リンク切れ・孤立・矛盾・データギャップ等）と改善提案 |
| `/wiki-topic <add\|list\|remove> [name] [desc]` | トピック／ページ種別の管理 |
| `/wiki-move <from-ref> <to-ref>` | ページの移動・改名（inbound リンク書換え込み） |

加えて、規約・手順を提供する知識スキル `llm-wiki` が Wiki 操作時に自動で参照される。

## 自動参照（暗黙参照）

2 つのフックで、Wiki を意識せず質問しても自動で参照される。

- **SessionStart** — セッション開始時に Wiki の所在・トピック・「回答前に index を参照せよ」という指示を注入。
- **UserPromptSubmit** — 質問が既存知識に関連すると判定したときのみ、参照リマインドを軽量注入。無関係な作業（コード編集等）では何もしない。

無効化したい場合は `~/.llm-wiki/config.yml` の `auto_reference: false`。Wiki 未初期化時は両フックとも無出力。

## ディレクトリ構造（`~/.llm-wiki/`）

```
~/.llm-wiki/
├── config.yml                 # トピック・種別の正本（人間/LLM 用）
├── log.md                     # 全操作の時系列（flock 保護で追記）
├── global/                    # 横断的・トピックに属さない知識
│   ├── raw/                   # 原典（不変。読むだけ）
│   ├── overview.md            # 俯瞰・統合テーゼ
│   ├── index.md               # カタログ
│   └── wiki/{papers,articles,concepts,entities,...}/
└── topics/<topic>/            # global と同一構造
```

- **スコープ** = `global` または `topics/<topic>`。
- **ページ種別** = 既定はコア4種（`papers` / `articles` / `concepts` / `entities`）。`decisions` / `queries` / `journal` 等は `/wiki-topic` でオプトイン追加。

## 規約（要点）

- **ファイル名 slug**: タイトルを決定論的にサニタイズして生成（日本語はそのまま保持。例「機械学習」→ `機械学習.md`）。手で命名しない。
- **リンク**: 正本はスコープ修飾の絶対形 `[[scope/page_type/slug]]`。短縮形 `[[slug]]` は同一ディレクトリ内のみ。
- **index.md**: 種別見出しごとに `- [[link]] — 一行要約 | kw: 検索語…`。`kw:` が日本語検索の弱点を補う。
- **log.md**: `## [YYYY-MM-DD HH:MM] <op> | <scope> | <title>`（`grep "^## \["` でパース可能）。
- **frontmatter 必須**: `title` / `page_type` / `scope` / `created` / `updated`。

詳細は skill 内 `skills/llm-wiki/references/conventions.md` を参照。

## 設計上の特徴

- **決定論で不確実性を最小化**: 構造生成・index/log 追記・リンク書換え・移動は `scripts/` のスクリプトに固定し、LLM には要約・統合・分類判断のみを委ねる。
- **変化への耐性**: 追加だけでなく rename / move / トピック再編を `wiki-move.sh` がリンク書換え込みで処理。
- **並行安全**: 単一グローバル Wiki への書き込みを `flock` で直列化。
- **外部依存最小**: `bash` / `python3` / `jq` / `flock` のみ（追加の YAML ツール等は不要）。

## 設定

| 項目 | 既定 | 説明 |
|------|------|------|
| `LLM_WIKI_HOME`（環境変数） | `$HOME/.llm-wiki` | Wiki の保存先 |
| `config.yml: auto_reference` | `true` | UserPromptSubmit の自動参照リマインド |
| `config.yml: page_types` | コア4種 | ページ種別の定義（オプトインで拡張） |
| `config.yml: topics` | `[]` | トピックの定義 |

## 開発者向け

プラグインの中身を修正・拡張したい場合はローカルクローンから起動する:

```bash
git clone https://github.com/roamer7038/llm-wiki-plugin
cd llm-wiki-plugin
claude --plugin-dir .
```

`scripts/` 以下のシェル/Python スクリプトが Wiki の構造操作（index 更新・log 追記・移動・検索）を担う。LLM が直接ファイルを書き換える部分を最小化する設計のため、新機能は基本的に `scripts/` への追加と対応するスキルの更新という形を取る。

## ライセンス

[MIT](LICENSE) © 2026 roamer7038
