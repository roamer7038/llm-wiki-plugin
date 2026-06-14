---
name: wiki-query
description: This skill should be used when the user asks to "wikiを参照して答えて", "wikiに質問", "ナレッジベースから調べて", or invokes /wiki-query. Answers a question by consulting the LLM Wiki index and pages, citing sources, and optionally filing the answer back as a queries page.
version: 0.1.0
---

# wiki-query — Wiki を参照して回答

LLM Wiki を参照して質問に答える。質問はユーザが呼び出し時に与えたもの。未指定なら尋ねる。

**大規模な多ホップ調査は `wiki-researcher` サブエージェントに委譲する。** 複数トピック横断・グラフ全体の合成・多数ページ読みが要る場合のみ起動し、`## 回答`＋`## 引用` を受け取る（委譲基準は `skills/llm-wiki/references/operations.md` の「サブエージェント委譲」）。単一ページ参照など軽い問いは委譲せず以下をインラインで行う。queries 還元（手順4）の判断・書き込みは委譲時も**本流**が行う。

1. 質問に関連するスコープを判断し、`<scope>/index.md` を Read する（global と該当 topic）。
2. 関連ページを辿って Read する。必要なら `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-search.sh "<query>" [scope]` で補助。
3. **参照したページを出典として明示**して回答する。Wiki に情報が無ければその旨を伝え、wiki-ingest での取り込みや Web 調査を提案する。
4. 回答が比較・分析など再利用価値を持つ場合、`queries` ページとして**還元するか確認**する。還元時はテンプレで作成し、`wiki-index-upsert.sh` と `wiki-log.sh query <scope> "<問い>" ...` を実行する。

規約・手順の詳細は llm-wiki スキルを参照。
