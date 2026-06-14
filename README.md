# llm-wiki

LLM が構築・維持・参照する、永続的・累積的なグラフ構造のナレッジベースを Claude Code に与えるプラグイン。
**本プラグインは開発中であり、効果の実証や安定性の保証はまだされていない。**

## コンセプト

本プラグインは Karpathy が提唱した [LLM Wiki]((https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)) パターンに触発され、
LLMに与える知識を「一過性のプロンプト」から「永続的なナレッジベース」へと進化させることを目指す。

一般的な RAG は問い合わせのたびに知識をゼロから再発見する。
LLM Wikiは、LLM がソースを取り込むたびに、要点を抽出して **既存の Wiki に統合**し、相互リンク・要約・矛盾の注記を維持する。
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
| `/wiki-new <title>` | ユーザ自身の知識を手動でページ化（テンプレ雛形を用意し、記述があれば下書き） |
| `/wiki-query <question>` | Wiki を参照し、出典付きで回答。良い回答は還元可 |
| `/wiki-lint [scope]` | 健全性チェック（リンク切れ・孤立・矛盾・データギャップ等）と改善提案 |
| `/wiki-topic <add\|list\|remove> [name] [desc]` | トピック／ページ種別の管理 |
| `/wiki-move` | ページの移動・改名、トピックの改名、リンクグラフ確認（inbound リンク書換え込み） |

加えて、規約・手順を提供する知識スキル `llm-wiki` が Wiki 操作時に自動で参照される。

素材の置き場・取り込みの流れ・人間による直接編集など、**日々の使い方のガイド**は [`docs/USAGE.md`](docs/USAGE.md) を参照。

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
- **リンク**: 正本はファイル実体パスに一致する絶対形 `[[scope/wiki/page_type/slug]]`。短縮形 `[[slug]]` は同一ディレクトリ内のみ。
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

---

## 開発者向け

```bash
git clone https://github.com/roamer7038/llm-wiki-plugin
cd llm-wiki-plugin
```

ローカルでの動作確認には 2 つの方法がある。

### 1. `--plugin-dir` で直接起動（最速）

marketplace を介さずローカルディレクトリから直接読み込む。コマンド／スキル／フックの開発はこれが最短。

```bash
claude --plugin-dir .
```

### 2. ローカル marketplace から install（配布フローの検証）

`displayName` / `category` / install UX まで含めて、実際の配布と同じ経路で確認したいとき。`marketplace.json` の `source: "./"` がローカルパス指定にもそのまま対応しているため、GitHub に push せずローカルディレクトリを marketplace として追加できる。

```
# GitHub 版を入れている場合、同名 llm-wiki と衝突するので先に外す
/plugin marketplace remove llm-wiki

# ローカルディレクトリを marketplace として追加し install
/plugin marketplace add ~/llm-wiki-plugin
/plugin install llm-wiki@llm-wiki

# ソースを編集したら反映
/plugin marketplace update llm-wiki
```

いずれの方法でも、**フック（`hooks.json`）の変更反映には Claude Code の再起動が必要**。

### スクリプトの単体テスト

テストフレームワークは無い。本物の `~/.llm-wiki` を汚さないよう、必ず一時 `LLM_WIKI_HOME` で手動検証する。外部依存は `bash` / `python3` / `jq` / `flock` のみ。

```bash
export LLM_WIKI_HOME="$(mktemp -d)/wiki"
bash scripts/wiki-init.sh
bash scripts/wiki-index-upsert.sh global concepts attention "注意機構" "attention, 注意"
bash scripts/wiki-validate.sh   # 健全性チェック（常に exit 0）
```

### 構成と設計

| ディレクトリ | 役割 |
|------|------|
| `scripts/*.sh` | 全操作の実体。構造生成・index/log 追記・リンク書換え・移動・slug 生成などの決定論処理。すべて `_lib.sh` を source する |
| `skills/` | `/wiki-*` コマンドの実体かつ自動トリガ。スクリプトを呼ぶ手順書。中核は知識スキル `llm-wiki`（規約・手順・テンプレートを保持） |
| `hooks/hooks.json` | 暗黙参照。`SessionStart` / `UserPromptSubmit` が `wiki-context.sh` を呼ぶ |

設計の核心は **決定論スクリプトと LLM 判断の分業**。間違えてはいけない定型操作は `scripts/` に固定し、LLM には要約・統合・分類・矛盾検出のみを委ねる。新機能も基本はこの境界を守り、`scripts/` への追加と対応スキルの更新という形を取る。

動作アーキテクチャ（自動／手動の境界・整理機構・蓄積ライフサイクル・人間による直接編集の運用）は [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) を参照。開発の詳細な規約・変更方針（オンディスク形式を変えるときの移行の仕掛けなど）は [`CLAUDE.md`](CLAUDE.md) を参照。機能変更時は `.claude-plugin/plugin.json` の `version` を更新し、`plugin.json` と `marketplace.json` で重複している説明文を揃えること。

## ライセンス

[MIT](LICENSE) © 2026 roamer7038
