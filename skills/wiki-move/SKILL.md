---
name: wiki-move
description: This skill should be used when the user asks to "ページを移動", "ページを改名", "wikiを再編", "概念を別トピックに移す", "rename a wiki page", or invokes /wiki-move. Moves or renames an LLM Wiki page (ref form scope/page_type/slug), rewriting inbound links and updating indexes.
version: 0.1.0
---

# wiki-move — ページの移動/改名

LLM Wiki のページを移動/改名する。ref 形式は `scope/page_type/slug`。移動元・移動先はユーザの指定に従う。未指定なら尋ねる。

1. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-move.sh "<from-ref>" "<to-ref>"` を実行する。
   - ファイル移動・frontmatter 更新・全 inbound `[[...]]` リンク書換え・両スコープ index 更新・log 追記を一括で行う。
2. 結果（書換えたファイル数）を報告する。
3. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-validate.sh` で移動後の健全性を確認し、リンク切れ等があれば報告する。

手で `mv` したり index を手書きしないこと（必ずこのスクリプト経由）。
