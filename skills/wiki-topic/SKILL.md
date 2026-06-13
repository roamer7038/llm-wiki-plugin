---
name: wiki-topic
description: This skill should be used when the user asks to "トピックを追加", "wikiのトピックを管理", "ページ種別を追加", "list topics", or invokes /wiki-topic. Adds, lists, or removes LLM Wiki topics (and page types), keeping config.yml and directories in sync.
version: 0.1.0
---

# wiki-topic — トピック/ページ種別の管理

LLM Wiki のトピックを管理する。サブコマンド（add / list / remove）と名前・説明はユーザの指定に従う。
ルートは `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-path.sh` で解決する（`<ROOT>` と表記）。

### list
`<ROOT>/config.yml` の `topics:` と、`<ROOT>/topics/` の実ディレクトリを両方示す。乖離があれば指摘する。

### add `<name>`（説明 `<desc>`）
config.yml とディレクトリを**同期して**追加する:
1. 既存の page_type ディレクトリを確認: `ls <ROOT>/global/wiki`
2. 同じ種別構成で新トピックを作成:
   - `mkdir -p <ROOT>/topics/<name>/raw` と、各 page_type について `<ROOT>/topics/<name>/wiki/<type>`
   - `<ROOT>/topics/<name>/index.md` に `# Index — topics/<name>` を作成
   - `<ROOT>/topics/<name>/overview.md` を overview テンプレから作成（scope を `topics/<name>` に）
3. config.yml の `topics:` に `- {name: <name>, desc: <desc>}` を追記（Edit）。`topics: []` の場合はリスト形式に直す。
4. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-log.sh topic "topics/<name>" "トピック追加: <name>"`

ページ種別を追加したい場合（例 decisions/queries/journal）は、同様に各スコープに `wiki/<種別>` を作り config の `page_types:` に追記する。

### remove `<name>`
**破壊的になりうるため確認を取る**。既存ページがある場合はデータを削除しない。既定では config.yml の `topics:` から該当エントリを外す（unregister）に留め、`<ROOT>/topics/<name>/` 配下の扱い（保持/別途手動削除）をユーザに確認する。実施後 `wiki-log.sh topic` に記録する。
