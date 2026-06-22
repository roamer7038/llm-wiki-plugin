---
name: wiki-ingest
description: This skill should be used when the user asks to "ソースを取り込む", "wikiに取り込む", "ナレッジベースに追加", "ingest", "記事/論文/URLをwikiに追加", or invokes /wiki-ingest. Ingests a source (file or URL) into the LLM Wiki, creating summary pages and updating related pages, index, and log with user confirmation.
version: 0.1.0
allowed-tools: Bash(*wiki-*.sh*) WebFetch(*)
---

# wiki-ingest — ソースの取り込み

ソース（ファイルパスまたは URL）を LLM Wiki に取り込む。

**本流（親）はオーケストレーションのみ。** 取り込み処理（ソース取得・raw 保存・重複検出・ページ案作成）は **必ず `wiki-source-analyst` エージェントに委譲する**。ソースの大小を問わず委譲する——本流がインラインで取り込みを実行することはない。

## 手順

1. **初期化確認**: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-path.sh` を実行。未初期化なら `/wiki-init` を案内して停止する。

2. **エージェント起動（必須）**: Agent ツールで `wiki-source-analyst` を起動する。
   - **複数ソースの場合**: ソースごとに 1 エージェントを**並列**で起動する。
   - エージェントへの指示に、ソース（URL またはパス）・希望トピック（あれば）を明示する。
   - エージェントが `raw/` への保存・重複検出・ページ案作成を行い、`## 取り込み提案` ブロックを返す。

3. **ユーザ確認**: 提案のスコープ・page_type・slug・本文ドラフトをユーザに提示し、承認を得る。

4. **書き込み（承認後・本流）**: 書き込みは flock 直列化のため本流に集約する。
   - slug を確認（エージェントが `wiki-slug.sh` で生成済みのものを使う）
   - テンプレを配置: `cp ${CLAUDE_PLUGIN_ROOT}/skills/llm-wiki/assets/templates/<page_type>.md <scope>/wiki/<page_type>/<slug>.md`
   - frontmatter と本文を埋める
   - 相互リンク（絶対形 `[[scope/wiki/page_type/slug]]`）を張る
   - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-index-upsert.sh <scope> <page_type> <slug> "<要約>" "<kw...>"`
   - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-log.sh ingest <scope> "<title>" "<bullet>..."`
   - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-validate.sh <scope>` で検証・報告

llm-wiki スキルの規約と `skills/llm-wiki/references/operations.md` の Ingest 手順に従うこと。
