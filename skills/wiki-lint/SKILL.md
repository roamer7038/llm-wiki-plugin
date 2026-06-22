---
name: wiki-lint
description: This skill should be used when the user asks to "wikiをlint", "wikiの健全性チェック", "wikiの整合性を確認", "ナレッジベースを点検", or invokes /wiki-lint. Runs health checks on the LLM Wiki (broken links, orphans, contradictions, data gaps) and proposes improvements.
version: 0.1.0
allowed-tools: Bash(*wiki-*.sh*)
---

# wiki-lint — Wiki の健全性チェック

LLM Wiki の健全性をチェックする。範囲はユーザ指定があればそのスコープ（`global` または `topics/<topic>`）、無ければ全体。

**本流（親）はオーケストレーションのみ。** 意味的監査は **必ず `wiki-auditor` エージェントに委譲する**——単一スコープでも常に委譲する。

## 手順

1. **機械検査（本流）**: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-validate.sh [scope]` を本流で実行し、結果（リンク切れ／孤立／index・config 整合／必須 frontmatter／superseded_by／index 肥大化／log 形式）を収集する。

2. **意味的監査（必須委譲）**: Agent ツールで `wiki-auditor` エージェントを起動する。
   - スコープ指定なし（全体）の場合: `global` ＋ 各 `topics/<topic>` を**並列**で起動する。
   - スコープ指定あり（単一スコープ）の場合でも: そのスコープで 1 エージェントを起動する。
   - 各エージェントが `## 監査結果` を返す。

3. **集約と報告**: 機械検査結果＋全エージェントの findings を集約してユーザに提示する。findings の観点:
   - 矛盾するページ対、陳腐化した記述
   - index に頻出するが専用ページの無い不足概念
   - 複数ページに頻出するが entities ページの無い固有名詞（entity 化でグラフ密度向上）
   - **Web 検索で埋められるデータギャップ**（具体的な検索クエリを提案）
   - **原典スナップショット未保存**（`source_id` を持つが `raw/` に抽出テキストが無いもの）
   - 次に調べるべき問い

4. 修正は**ユーザ確認後**に本流で適用する。適用したら index/log をスクリプトで更新する。

検査のみで自動修正はしない（提案に留め、承認を得てから直す）。
