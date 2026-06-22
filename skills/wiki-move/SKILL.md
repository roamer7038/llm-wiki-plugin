---
name: wiki-move
description: This skill should be used when the user asks to "ページを移動", "ページを改名", "トピックを改名/リネーム", "wikiを再編", "概念を別トピックに移す", "リンクの繋がりを見たい/被リンクを調べる", "rename a wiki page or topic", or invokes /wiki-move. Moves/renames an LLM Wiki page or whole topic (rewriting inbound links and indexes), and inspects the link graph.
version: 0.2.0
allowed-tools: Bash(*wiki-*.sh*)
---

# wiki-move — ページ／トピックの移動・改名とグラフ確認

LLM Wiki の再編を行う。ファイル移動・frontmatter 更新・**全 inbound `[[...]]` リンク書換え**・index 更新・log 追記をスクリプトが一括処理する。手で `mv` したり index を手書きしないこと（リンク切れの原因）。

再編の前後で `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-links.sh <ref>` を使い、**何が壊れるか（被リンク）を確認**してから実行すると安全。

## ページの移動・改名（ref 形式 `scope/wiki/page_type/slug`）

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-move.sh "<from-ref>" "<to-ref>"
```
- 例: `wiki-move.sh global/wiki/concepts/機械学習 topics/ml/wiki/concepts/機械学習`
- ファイル移動・frontmatter（scope/page_type/updated）更新・全 inbound リンク書換え・両スコープ index 更新・log を一括実行。

## トピックの改名（サブツリーごと）

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-rename-topic.sh <old> <new>
```
- 例: `wiki-rename-topic.sh ml machine-learning`（トピック名のみ指定。`topics/` や `/` は付けない）
- `topics/<old>` をまるごと改名し、配下全ページの scope・全 wiki の `[[topics/<old>/...]]` リンク・config.yml の topics 名・各 index を更新する。

## リンクグラフの確認（read-only）

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-links.sh <ref> [--inbound|--outbound]
bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-traverse.sh <ref> [--depth N] [--outbound|--inbound|--both]
bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-graph.sh [--summary|--json|--dot] [scope]
```
- `wiki-links`: 1 ホップの outbound / inbound / index 掲載状況。再編の影響確認・孤立調査に。
- `wiki-traverse`: 起点から N ホップ辿って近傍ページを index 要約つきで収集（既定 depth=2, both）。関連文脈の収集に。
- `wiki-graph`: グラフ全体の俯瞰。連結成分（島）・孤立ページ・被リンクハブ・リンク切れを一覧。

## 手順

1. 対象 ref（と移動先）を確認。未指定なら尋ねる。
2. `wiki-links.sh` で被リンクを確認し、影響範囲を把握。
3. ページなら `wiki-move.sh`、トピックなら `wiki-rename-topic.sh` を実行。
4. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-validate.sh` で健全性を確認し、リンク切れ等があれば報告する。

規約・手順の詳細は llm-wiki スキルを参照。
