---
name: wiki-init
description: This skill should be used when the user asks to "wikiを初期化", "LLM Wikiをセットアップ", "set up the wiki", "wikiを作る", or invokes /wiki-init. Initializes the LLM Wiki at ~/.llm-wiki with the default structure and config.
version: 0.1.0
---

# wiki-init — LLM Wiki の初期化

LLM Wiki を初期化する。

1. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-init.sh` を実行し、構造とデフォルト config を冪等生成する。
2. 結果サマリを報告する。
3. `~/.llm-wiki/config.yml`（または `$LLM_WIKI_HOME/config.yml`）を Read して提示し、ユーザに最初のトピックを設定するか尋ねる。追加する場合は wiki-topic スキル（`/wiki-topic add <name> <desc>`）を案内するか、その場で実行する。

既定のページ種別はコア4種（papers/articles/concepts/entities）。decisions/queries/journal 等はオプトインであることを伝える。
Wiki の構造・規約の詳細は llm-wiki スキルを参照。
