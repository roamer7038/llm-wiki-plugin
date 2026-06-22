---
name: wiki-new
description: This skill should be used when the user wants to write their own knowledge into the wiki — "新しいページを作りたい", "こういうナレッジを書きたい", "メモを残したい", "wikiにページを追加（手動で）", "scaffold a wiki page", or invokes /wiki-new. Scaffolds a new LLM Wiki page from a template with frontmatter pre-filled, optionally drafting the body from the user's description. Distinct from wiki-ingest (which is source-driven); this is for the user's own knowledge.
version: 0.1.0
allowed-tools: Bash(*wiki-*.sh*)
---

# wiki-new — 手動でナレッジページを作る

ユーザ自身の頭の中にある知識を新しいページとして起こす。ソース（URL/ファイル）からの取り込みは `wiki-ingest` を使う — こちらは**ユーザの記述駆動**。

呼び出し: `/wiki-new <title>`、または「こういうナレッジを書きたい」という依頼。タイトル・内容が未指定なら尋ねる。

1. 未初期化なら `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-path.sh` で確認し、wiki-init を促す。
2. ユーザの記述から **page_type とスコープを判断し、提示して確認を取る**。
   - 種別: concepts（横断概念）/ entities（人物・組織・プロダクト）/ articles・papers（要約物）/ オプトイン種別（decisions/queries/journal）。
   - スコープ: 既存トピックに属す → `topics/<topic>`／どこにも収まらない新領域 → 新トピック提案（`/wiki-topic add`）／横断的 → `global`。
3. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-search.sh "<title/別名>"` で**重複確認**。既存があれば新規作成せず、そのページの編集・更新に倒す。
4. 雛形を作成する:
   ```
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-new.sh <scope> <page_type> "<title>" ["<一行要約>"] ["<kw...>"]
   ```
   slug 生成・テンプレ配置・frontmatter（title/page_type/scope/created/updated）記入・index upsert（要約を渡したとき）・log 追記を一括で行い、作成パスを返す。
5. 本文を埋める:
   - ユーザが内容を語っている場合は、その内容で本文を**下書き**する（テンプレの `<...>` placeholder を実内容に置換）。
   - まだ書けない場合は placeholder のまま残し、「ここに書いてください」と渡してよい。
6. **相互リンク**: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-links.sh <ref>` や `wiki-search.sh` で近傍ページを探し、関連があれば本文に絶対形 `[[scope/page_type/slug]]` でリンクを張る（双方向にすると孤立を防げる）。**使わなかったテンプレの placeholder リンク `[[<...>]]` は削除する**。
7. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-validate.sh <scope>` で検証。孤立警告が残る場合は手順6でリンクを補えないか検討する。

規約・テンプレートの詳細は llm-wiki スキルを参照。
