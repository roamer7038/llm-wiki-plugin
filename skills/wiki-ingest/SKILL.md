---
name: wiki-ingest
description: This skill should be used when the user asks to "ソースを取り込む", "wikiに取り込む", "ナレッジベースに追加", "ingest", "記事/論文/URLをwikiに追加", or invokes /wiki-ingest. Ingests a source (file or URL) into the LLM Wiki, creating summary pages and updating related pages, index, and log with user confirmation.
version: 0.1.0
---

# wiki-ingest — ソースの取り込み

ソース（ファイルパスまたは URL）を LLM Wiki に取り込む。取り込み対象とトピックは、ユーザが呼び出し時に指定したもの（例: `/wiki-ingest <path-or-url> [topic]`）。未指定なら尋ねる。

**重い／複数ソースは `wiki-source-analyst` サブエージェントに委譲する。** 委譲基準・返却フォーマットは `skills/llm-wiki/references/operations.md` の「サブエージェント委譲」を参照。

- **委譲する場合**（長い記事・PDF・複数ソース）: ソースごとに `wiki-source-analyst` を起動（複数は並列）。生ソースの取得・raw 保存・重複検出・ページ案作成までをエージェントが行い、`## 取り込み提案` ブロックを返す。本流は提案を**ユーザに確認** → 承認後に下記 5〜8（ページ書き込み・index・log・validate）を**本流で**実行する。書き込みは flock 直列化のため本流に集約する。
- **委譲しない場合**（小さい単一ソース）: 以下の手順をインラインで実行する。

llm-wiki スキルと `skills/llm-wiki/references/operations.md` の Ingest 手順に厳密に従うこと。要点:

1. 未初期化なら `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-path.sh` で確認し、wiki-init を促す。
2. 対象を取得（URL は WebFetch、ローカルは Read）し、取得元メタ（URL・取得日・`source_id`）を該当 `<scope>/raw/sources.md` に記録、**読んだ抽出テキストを `<scope>/raw/` にスナップショット保存**する（原則保存。省略は著作権／巨大バイナリ／恒久 URL の例外時のみ、理由を sources.md に記す）。`source_id`（URL 正規化 or ファイル hash）を控える。
3. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-search.sh "<title/alias/source_id>"` で**重複を確認**。既存なら更新に倒す。
4. 要点・該当 page_type・スコープ案を提示し、**ユーザの確認を取る**。スコープ選定:
   - 既存トピックに明確に属する → `topics/<topic>`
   - どのトピックにも収まらない、または新しい知識領域 → **新トピックの作成を積極的に提案する**（`/wiki-topic add` を使う）。既存に無理に収めない。
   - 汎用・横断的な内容 → `global`
5. 承認後、テンプレ（`${CLAUDE_PLUGIN_ROOT}/skills/llm-wiki/assets/templates/<page_type>.md`）を配置して埋める。slug は `wiki-slug.sh "<title>"` で生成。
6. 波及更新は範囲を限定（直接言及 entity/concept ＋ index の kw 一致ページのみ）。相互リンクは絶対形 `[[scope/page_type/slug]]`。
7. `wiki-index-upsert.sh` で index 更新、`wiki-log.sh ingest <scope> "<title>" ...` で log 追記。
8. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-validate.sh <scope>` で検証し、問題があれば報告。
