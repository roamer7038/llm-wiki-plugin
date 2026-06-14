# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

これは Claude Code プラグイン `llm-wiki` の**ソースリポジトリ**である。プラグインが操作する Wiki データ本体（`~/.llm-wiki/`）はここには含まれない。両者を混同しないこと。

動作アーキテクチャの全体像（4層構成・自動/手動の境界・整理機構・蓄積ライフサイクル・人間による直接編集の運用）は [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) にまとめてある。Claude Code ランタイムとの接合面（フックの注入文・タイミング・やっていないこと）の厳密仕様は [`docs/CLAUDE_CODE_INTEGRATION.md`](docs/CLAUDE_CODE_INTEGRATION.md) を参照。

## 2つの世界を分けて考える

| | プラグインリポジトリ（ここ） | Wiki データ |
|---|---|---|
| 場所 | このリポジトリ | `~/.llm-wiki/`（`LLM_WIKI_HOME` で上書き可） |
| 中身 | scripts / skills / hooks | ユーザのナレッジページ・index・log |
| 編集対象 | 機能開発で触る | スクリプト経由でのみ変更（手書き禁止） |

このリポジトリでの開発作業は前者。後者を直接編集してはならない。

## 開発・動作確認

```bash
# プラグインをローカルから起動して動作確認
claude --plugin-dir .

# スクリプト単体テスト（本物の ~/.llm-wiki を汚さないため必ず一時ルートを使う）
export LLM_WIKI_HOME="$(mktemp -d)/wiki"
bash scripts/wiki-init.sh
bash scripts/wiki-index-upsert.sh global concepts attention "注意機構" "attention, 注意"
bash scripts/wiki-validate.sh        # 健全性チェック（常に exit 0）
```

テストフレームワークは無い。スクリプトは上記のように一時 `LLM_WIKI_HOME` で手動検証する。外部依存は `bash` / `python3` / `jq` / `flock` のみ。

## アーキテクチャの核心

**決定論スクリプトと LLM 判断の分業がこの設計の根幹。** 構造生成・index/log 追記・リンク書換え・移動・slug 生成といった「間違えてはいけない定型操作」は `scripts/` に固定し、LLM には要約・統合・分類・矛盾検出という「判断を要する作業」のみを委ねる。新機能を足すときもこの境界を守る — 定型操作はスクリプトへ、判断はスキルの手順へ。

### 3層構成

1. **`scripts/*.sh`** — 全操作の実体。すべて `_lib.sh` を source する。
   - read 系: `wiki-path` / `wiki-search` / `wiki-validate` / `wiki-context` / `wiki-slug` / `wiki-links` / `wiki-graph`（全グラフ俯瞰・島検出）/ `wiki-traverse`（N ホップ近傍収集）
   - write 系: `wiki-init` / `wiki-index-upsert` / `wiki-log` / `wiki-new` / `wiki-move` / `wiki-rename-topic`
   - 複雑なテキスト操作（index 編集・move・rename・validate・links）は bash 内のヒートドキュメント Python で実装し、値は環境変数で受け渡す。
2. **`skills/`** — `/wiki-*` コマンドの実体かつ自動トリガ。各スキルはスクリプトを呼ぶ手順書。`llm-wiki` が中核の知識スキルで規約と手順を持ち、`references/conventions.md`（規約全文）・`references/operations.md`（手順詳細）・`assets/templates/*.md`（ページ雛形）を参照する。
3. **`hooks/hooks.json`** — 暗黙参照。`SessionStart` と `UserPromptSubmit` の両方が `wiki-context.sh` を呼ぶ（引数 `session` / `prompt`）。

### `_lib.sh` が提供する共通基盤

- `wiki_root()` — `LLM_WIKI_HOME` → `$HOME/.llm-wiki` の解決。
- `wiki_exists()` — 未初期化判定。**read 系・フックは未初期化なら無出力で exit 0**（セッションを止めない）。
- `acquire_write_lock()` — `$root/.lock/wiki.lock` への単一グローバル flock。**write 系スクリプトは書き込み前に必ずこれを呼ぶ**。単一 Wiki を複数セッションが触りうるための直列化。

## 変更の方針 — 壊すのは Wiki データだけは避ける

**プラグイン自身に後方互換は不要。** スクリプトのインタフェース・リンクや index/log の形式・slug 規則・既定種別、どれも自由に変えてよい。変更を恐れる必要はない。整理・改善・破壊的変更は積極的にやる。

守るべき唯一の不変条件は **ユーザが既に運用している `~/.llm-wiki/` のデータを黙って壊さないこと。** 後方互換のために設計を妥協するのではなく、**破壊的変更に「移行の仕掛け」を必ず添える**ことで対応する。

オンディスク形式・規約（slug 規則 / リンク形式 / index・log のフォーマット / frontmatter スキーマ / ディレクトリ構造）を変えるときは、次のどちらかを必ず用意する:

- **移行スクリプト** — 既存データを一括で新形式へ書き換える `scripts/`（リンク全置換のような機械的変換はこちら。`wiki-move.sh` の link-rewrite、サブツリー一括変換は `wiki-rename-topic.sh` が参考実装）。冪等に作り、適用前後で `wiki-validate.sh` が通ること。
- **LLM 主導の移行手順** — 機械化しづらい変換は、スキルに「旧形式を検出して新形式へ直す」手順を書き、LLM に任せる。これは LLM 運用 Wiki の強みで、決定論スクリプトに固執しなくてよい。

実装の指針:

- 形式変更を入れる前に、既存 Wiki にその旧形式データが残りうることを前提に「検出 → 変換」を設計する。新規ロジックだけ更新して既存データを置き去りにしない。
- `config.yml` には `version` フィールドがある（`wiki-init.sh` が `version: 1` を書く）が、現状は移行検出に使っていない。形式・スキーマを変えるときはこの版を上げ、「どの版のデータか」を判別して移行を確実にすることを推奨。
- `wiki-init.sh` の冪等性（既存ファイルを上書きしない）は移行の安全弁として価値があるので、初期化と移行は分けて考える。

参考に、現状の主要な on-disk 契約（変えてよいが移行を伴うもの）:

- slug: ASCII 小文字化／日本語そのまま保持／漢字ローマ字化はしない（`wiki-slug.sh`）。
- リンク: `[[scope/wiki/page_type/slug]]`（ファイル実体パスに一致。同一ディレクトリのみ短縮形可）。
- index 行: `- [[link]] — 要約 | kw: …`。log: `## [YYYY-MM-DD HH:MM] op | scope | title`（いずれも grep パース前提）。
- config.yml は機械パースせず、topics/page_types はディレクトリ構造から列挙。
- 既定はコア4種（papers/articles/concepts/entities）、その他はオプトイン。

## フックの出力契約

`wiki-context.sh` は JSON `{"hookSpecificOutput":{"hookEventName":..,"additionalContext":..}}` を stdout に出す（`jq` で生成）。未初期化時は無出力 exit 0。`UserPromptSubmit` の自動参照は `config.yml: auto_reference: false` で抑止。

## 既知の状態

- **Proactive Capture（取り込み提案）は SessionStart 注入文に判定基準を畳み込む方式**（`wiki-context.sh` session モード）で実現する。Stop フックでは実装しない — 毎ターン発火してノイズになるため。

## バージョン同期

機能変更時は `.claude-plugin/plugin.json` の `version` を更新する。説明文は `plugin.json` と `.claude-plugin/marketplace.json` の両方に重複しているため、変更時は両方を合わせる。
