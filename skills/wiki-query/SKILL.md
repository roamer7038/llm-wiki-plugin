---
name: wiki-query
description: This skill should be used when the user asks to "wikiを参照して答えて", "wikiに質問", "ナレッジベースから調べて", or invokes /wiki-query. Answers a question by consulting the LLM Wiki index and pages, citing sources, and optionally filing the answer back as a queries page.
version: 0.1.0
allowed-tools: Bash(*wiki-*.sh*)
---

# wiki-query — Wiki を参照して回答

LLM Wiki を参照して質問に答える。

**本流（親）はオーケストレーションのみ。** Wiki ページを読む必要があるあらゆる問いは **必ず `wiki-researcher` エージェントに委譲する**——単一ページ参照でも常に委譲する。

## 手順

1. **エージェント起動（必須）**: Agent ツールで `wiki-researcher` を起動する。
   - エージェントへの指示に、ユーザの問い全文を明示する。
   - エージェントが Wiki を辿り、出典付き回答（`## 回答`＋`## 引用`）を返す。

2. **結果の提示**: エージェントの回答と引用リストをユーザに提示する。

3. **queries 還元**: 回答が比較・分析など再利用価値を持つ場合、`queries` ページとして**還元するか確認**する。
   - 還元時: テンプレで作成 → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-index-upsert.sh` → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-log.sh query <scope> "<問い>" ...`

**インラインで答えてよい例外**: Wiki ページを読む必要が明らかにない問い（「トピック一覧を見せて」「index の件数は？」など、セッション開始時の注入情報だけで答えられるもの）。

規約・手順の詳細は llm-wiki スキルを参照。
