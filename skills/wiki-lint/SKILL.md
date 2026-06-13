---
name: wiki-lint
description: This skill should be used when the user asks to "wikiをlint", "wikiの健全性チェック", "wikiの整合性を確認", "ナレッジベースを点検", or invokes /wiki-lint. Runs health checks on the LLM Wiki (broken links, orphans, contradictions, data gaps) and proposes improvements.
version: 0.1.0
---

# wiki-lint — Wiki の健全性チェック

LLM Wiki の健全性をチェックする。範囲はユーザ指定があればそのスコープ（`global` または `topics/<topic>`）、無ければ全体。

1. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-validate.sh [scope]` を実行し、機械検査の結果（リンク切れ／孤立／index・config 整合／必須 frontmatter／superseded_by／index 肥大化／log 形式）を報告する。
2. さらに LLM の観点で点検し、`skills/llm-wiki/references/operations.md` の Lint 手順に従って以下を提案する:
   - 矛盾するページ対、陳腐化した記述、孤立ページの扱い
   - index に頻出するが専用ページの無い不足概念
   - **Web 検索で埋められるデータギャップ**（具体的な検索クエリを提案）
   - 次に調べるべき問い
3. 修正は**ユーザ確認後**に適用する。適用したら index/log をスクリプトで更新する。

検査のみで自動修正はしない（提案に留め、承認を得てから直す）。
