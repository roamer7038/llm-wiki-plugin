---
name: llm-wiki
description: This skill should be used when the user asks to "wikiに取り込む", "ナレッジベースに追加/更新", "ソースを取り込む", "ingest", "知識を整理", "wikiを参照して答えて", "wikiをlint/健全性チェック", "ページを移動/改名", "トピックを追加", or otherwise builds, maintains, queries, or reorganizes the personal LLM Wiki at ~/.llm-wiki. Provides the structure, conventions, and deterministic scripts for ingesting sources, answering with citations, linting, and moving pages.
version: 0.1.0
allowed-tools: Bash(*wiki-*.sh*) WebFetch(*)
---

# LLM Wiki 運用

LLM Wiki は `~/.llm-wiki/`（既定。`LLM_WIKI_HOME` で上書き可）にある、LLM が構築・維持する永続的・累積的なナレッジベースである。ソースを取り込むたびに要約ページを生成し、相互リンク・index・log を維持する。**定型操作（構造生成・index/log 追記・リンク書換え・移動）は決定論スクリプトに固定**し、LLM は要約・統合・分類判断・矛盾検出を担う。

スクリプトは `${CLAUDE_PLUGIN_ROOT}/scripts/` にある。詳細手順は `references/operations.md`、規約の全文は `references/conventions.md` を参照。

## 構造（要約）

```
~/.llm-wiki/
  config.yml                  # トピック・種別の正本（人間/LLM 用。スクリプトは機械パースしない）
  log.md                      # 全操作の時系列（flock 保護で追記）
  global/                     # 横断的・トピックに属さない知識
    raw/                      # 原典スナップショット＋取得元メタ（不変。読むだけ）
    overview.md               # 俯瞰・統合テーゼ
    index.md                  # カタログ
    wiki/{papers,articles,concepts,entities,...}/
  topics/<topic>/             # global と同一構造
```

- **スコープ** = `global` または `topics/<topic>`。
- **既定ページ種別** = papers / articles / concepts / entities。decisions / queries / journal 等はオプトイン（`/wiki-topic` で追加）。

## まず確認すること

- Wiki が未初期化なら `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-path.sh` で確認し、`/wiki-init` を促す。
- 知識を要する質問では、**回答前に該当スコープの `index.md` を Read** し、関連ページを辿って出典付きで答える。

## 規約（必須）

- **ページ frontmatter**: `title` / `page_type` / `scope` / `created` / `updated` は必須。種別ごとの追加メタは `references/conventions.md` とテンプレート参照。
- **ファイル名 slug**: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-slug.sh "<title>"` で決定論的に生成する（手で命名しない）。日本語はそのまま保持される。
- **リンク**: 正本はスコープ修飾の絶対形 `[[scope/page_type/slug]]`。短縮形 `[[slug]]` は同一ディレクトリ内のみ。
- **重複防止**: 新規ページ作成前に必ず `wiki-search.sh "<title or alias>"` で既存を検索し、あれば**更新に倒す**。
- **index / log / 移動は手書きしない**。下記スクリプトを使う。

## 操作と使うスクリプト

**本流（親）はオーケストレーションのみ。** Ingest・Query・Lint のいずれも、read・判断フェーズは各スキルの手順に従いサブエージェントに委譲する。本流はユーザ確認と書き込みに専念する。

### Ingest（取り込み・確認付き）
**`wiki-source-analyst` エージェントに必ず委譲する**（ソースの大小不問）。詳細は `/wiki-ingest` スキルを参照。要点:
1. `wiki-path.sh` で初期化確認。
2. Agent ツールで `wiki-source-analyst` を起動（複数ソースなら並列）。エージェントが raw 保存・重複検出・ページ案を返す。
3. 提案をユーザに確認。
4. 承認後に本流でページ作成・index/log 更新・validate。スコープ選定の指針:
   - 既存トピックに明確に属する → `topics/<topic>`
   - どのトピックにも収まらない、または新しい知識領域 → **新トピックの作成を積極的に提案する**（`/wiki-topic add` を使う）。既存に無理に収めない。
   - 汎用・横断的な内容 → `global`

### Query（参照）
**`wiki-researcher` エージェントに必ず委譲する**（Wiki ページを読む必要があるあらゆる問い）。詳細は `/wiki-query` スキルを参照。要点:
1. Agent ツールで `wiki-researcher` を起動。エージェントが出典付き回答を返す。
2. 回答をユーザに提示。価値ある分析は queries ページとして**還元するか確認**し、還元時は index/log もスクリプトで更新。
- **例外**: Wiki ページを読む必要が明らかにない問いはインライン回答可（トピック一覧・index 件数など、注入情報だけで答えられるもの）。

### Lint（健全性チェック）
**`wiki-auditor` エージェントに必ず委譲する**（単一スコープでも起動）。詳細は `/wiki-lint` スキルを参照。要点:
1. 本流で `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-validate.sh [scope]` を実行（機械検査）。
2. Agent ツールで `wiki-auditor` を起動（全体なら各スコープを並列）。エージェントが意味的 findings を返す。
3. 集約してユーザに提示。修正適用はユーザ確認後。

### New（手動ページ作成）
- ユーザ自身の知識をページ化するときは `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-new.sh <scope> <page_type> "<title>" ["<要約>"] ["<kw>"]`。slug 生成・テンプレ配置・frontmatter 記入・index/log を一括。詳細手順は `/wiki-new` スキル。
- ソース駆動の取り込みは Ingest を使う（別物）。

### Move / Rename / 再編
- ページ移動・改名: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-move.sh <from-ref> <to-ref>`（ref 形式 `scope/wiki/page_type/slug`）。
- トピック改名（サブツリーごと）: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-rename-topic.sh <old> <new>`（トピック名のみ）。
- いずれも inbound リンク書換え・index・log を一括処理。**手で mv しない**。

### Links / グラフ（read-only）
- `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-links.sh <ref> [--inbound|--outbound]` — 1 ホップの被リンク・発リンク・index 掲載。再編の影響確認・孤立調査に。
- `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-traverse.sh <ref> [--depth N] [--outbound|--inbound|--both]` — 起点から N ホップ辿り近傍ページを index 要約つきで収集。**回答前の文脈集め**に使う（検索で起点を見つけ→辿る）。
- `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-graph.sh [--summary|--json|--dot] [scope]` — グラフ全体の俯瞰。連結成分（島）・孤立ページ・被リンクハブ・リンク切れを一覧。
- ref は `scope/wiki/page_type/slug` 形式（ファイルパスに一致）。

### トピック / 種別の追加
- `/wiki-topic` を使う（config.yml 更新とディレクトリ作成を同期）。

### 履歴 / 復旧（Git・自動）
- Wiki は git で自動版管理される（`config.yml: git: true`、git 未導入なら自動無効・write は成功）。**Stop フックがターン毎に 1 コミット**するので手動コミットは不要。
- `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-history.sh [scope] [count]` — 変更履歴を表示。
- `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-restore.sh <hash>` — 指定状態へ**非破壊で巻き戻す**（前進のみ・復元も巻き戻せる）。「取り消したい/前に戻したい」と言われたら history で候補提示 → 合意の上で restore。
- バイナリ原典（PDF・画像・Office 等）は `.gitignore` で対象外。版管理は知識テキスト(.md)のみ。

## 自発的な取り込み提案（Proactive Capture）

以下に該当する場合、ユーザーへの回答の末尾で wiki-ingest での取り込みを**一言提案する**（同一セッション内で繰り返さない）:

- Web 検索・外部ドキュメント調査で新たな知見・ベストプラクティスを発見した
- 複雑な問題の根本原因と解決策を突き止めた（再現性のある問題）
- 複数ソースを比較・合成し、再利用価値のある結論を出した

**提案しない場合**: 既に Wiki に存在する内容 / 一時的なデバッグ作業 / 単純なコード編集 / 会話自体が Wiki 操作の一部である場合。

提案は最後に一言: 「この内容を Wiki に取り込みますか？」。承認後に Ingest 手順（上記）を実行する。

## 不確実性を減らす原則

- パス・種別・トピックは推測せず、ディレクトリ構造と config を確認する。
- 命名・index・log・リンク・移動は**必ずスクリプト経由**。手作業の追記・書換えをしない。
- 作業後に `wiki-validate.sh` で健全性を確認する。

## 参照

- `references/conventions.md` — frontmatter / リンク / index / log の規約全文
- `references/operations.md` — ingest / query / lint / move の詳細手順とチェックリスト
