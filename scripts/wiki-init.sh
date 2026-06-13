#!/bin/bash
# Wiki 構造を冪等に初期化する（write）。既存ファイルは壊さない。
# 既定 page_types はコア4種（papers/articles/concepts/entities）。
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

root="$(wiki_root)"
CORE_TYPES=(papers articles concepts entities)

acquire_write_lock

created=()
note() { created+=("$1"); }

ensure_dir() { [ -d "$1" ] || { mkdir -p "$1"; note "dir  $1"; }; }
ensure_file() { # path, content
  if [ ! -f "$1" ]; then printf '%s' "$2" > "$1"; note "file $1"; fi
}

# ルートと global スコープ
ensure_dir "$root"
ensure_dir "$root/global/raw"
for t in "${CORE_TYPES[@]}"; do ensure_dir "$root/global/wiki/$t"; done
ensure_dir "$root/topics"
ensure_dir "$root/.lock"

# config.yml（無ければ既定を生成）
ensure_file "$root/config.yml" 'version: 1
language: ja
# 自動参照(UserPromptSubmit リマインド)を無効化したい場合は次を false に
auto_reference: true
# 既定は最小コア4種。decisions/queries/journal 等はオプトイン（/wiki-topic add で追加）。
page_types:
  - {name: papers,   desc: 論文の要約}
  - {name: articles, desc: 記事の要約}
  - {name: concepts, desc: 横断的な概念}
  - {name: entities, desc: 人物・組織・プロダクト・場所}
# オプトイン例（既定では作成しない）:
#  - {name: decisions, desc: 決定ログ}
#  - {name: queries,   desc: 問い合わせ結果の還元}
#  - {name: journal,   desc: 日付付きの経験・メモログ}
topics: []
'

# log.md
ensure_file "$root/log.md" '# LLM Wiki ログ

'

# global の index.md / overview.md
ensure_file "$root/global/index.md" '# Index — global
'
ensure_file "$root/global/overview.md" '---
title: global 俯瞰
scope: global
updated: '"$(date +%F)"'
---

# global 俯瞰・統合テーゼ

（横断的知識の全体像と、現時点の統合的な見立てをここに維持する。）
'

# init をログに記録（直接追記。ロック保持中）
if ! grep -q '^## \[' "$root/log.md" 2>/dev/null; then :; fi
printf '## [%s] init | global | Wiki 初期化\n- 構造とデフォルト config を生成\n\n' \
  "$(date '+%F %H:%M')" >> "$root/log.md"

# 結果サマリ
if [ "${#created[@]}" -eq 0 ]; then
  echo "既に初期化済み（変更なし）: $root"
else
  echo "初期化しました: $root"
  printf '  + %s\n' "${created[@]}"
fi
