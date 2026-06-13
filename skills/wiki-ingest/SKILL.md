---
name: wiki-ingest
description: This skill should be used when the user asks to "ソースを取り込む", "wikiに取り込む", "ナレッジベースに追加", "ingest", "記事/論文/URLをwikiに追加", or invokes /wiki-ingest. Ingests a source (file or URL) into the LLM Wiki, creating summary pages and updating related pages, index, and log with user confirmation.
version: 0.1.0
---

# wiki-ingest — ソースの取り込み

ソース（ファイルパスまたは URL）を LLM Wiki に取り込む。取り込み対象とトピックは、ユーザが呼び出し時に指定したもの（例: `/wiki-ingest <path-or-url> [topic]`）。未指定なら尋ねる。

llm-wiki スキルと `skills/llm-wiki/references/operations.md` の Ingest 手順に厳密に従うこと。要点:

1. 未初期化なら `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-path.sh` で確認し、wiki-init を促す。
2. 対象を取得（URL は WebFetch、ローカルは Read）し、原典を該当 `<scope>/raw/` に保存。`source_id`（URL 正規化 or ファイル hash）を控える。
3. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-search.sh "<title/alias/source_id>"` で**重複を確認**。既存なら更新に倒す。
4. 要点・該当 page_type・スコープ（トピック指定があれば topics/<topic>、無ければ判断。曖昧なら global）案を提示し、**ユーザの確認を取る**。
5. 承認後、テンプレ（`${CLAUDE_PLUGIN_ROOT}/skills/llm-wiki/assets/templates/<page_type>.md`）を配置して埋める。slug は `wiki-slug.sh "<title>"` で生成。
6. 波及更新は範囲を限定（直接言及 entity/concept ＋ index の kw 一致ページのみ）。相互リンクは絶対形 `[[scope/page_type/slug]]`。
7. `wiki-index-upsert.sh` で index 更新、`wiki-log.sh ingest <scope> "<title>" ...` で log 追記。
8. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-validate.sh <scope>` で検証し、問題があれば報告。
