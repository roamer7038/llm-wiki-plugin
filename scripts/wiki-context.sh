#!/bin/bash
# フック本体（read-only）。mode = session | prompt。
# 出力契約: JSON {"hookSpecificOutput":{"hookEventName":..,"additionalContext":..}}
# Wiki 未初期化なら無出力で exit 0。
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

mode="${1:-session}"
root="$(wiki_root)"

# 未初期化なら何もしない
wiki_exists || exit 0

emit() { # event, context
  jq -nc --arg ev "$1" --arg ctx "$2" \
    '{hookSpecificOutput:{hookEventName:$ev,additionalContext:$ctx}}'
}

# ディレクトリ構造から topics / page_types を列挙（config は機械パースしない）
list_dirs() { # parent
  [ -d "$1" ] || return 0
  find "$1" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort || true
}
join_csv() { paste -sd, - | sed 's/,/, /g'; }
topics="$(list_dirs "$root/topics" | join_csv || true)"
ptypes="$(list_dirs "$root/global/wiki" | join_csv || true)"
[ -n "$topics" ] || topics="(なし)"

if [ "$mode" = "session" ]; then
  ctx="[LLM Wiki] $root にナレッジベースがあります。
トピック: $topics
ページ種別: $ptypes
知識・事実・調査を要する質問に答える前に、該当スコープの index.md（例: $root/global/index.md）を Read し、関連ページを辿ってから出典付きで回答すること。
このセッションで、Web 調査による新たな知見・複雑な問題の根本原因と解決策・複数ソースを合成した再利用価値ある結論が得られたら、回答末尾で wiki-ingest による取り込みを一言提案すること（既存知識・一時的なデバッグ・単純な編集では提案しない。同一セッションで繰り返さない）。
取り込み・整理・lint・移動などの操作は llm-wiki スキルの手順に従う。"
  emit "SessionStart" "$ctx"
  exit 0
fi

# ---- prompt モード（UserPromptSubmit） ----
# config で auto_reference: false なら無効
if grep -qE '^auto_reference:[[:space:]]*false' "$root/config.yml" 2>/dev/null; then
  exit 0
fi

input="$(cat || true)"
prompt="$(printf '%s' "$input" | jq -r '.prompt // .user_prompt // empty' 2>/dev/null || true)"
[ -n "$prompt" ] || exit 0

# 照合キーワード: 各 index.md の kw: 行のみ（軽量・上限）＋ トピック名
kws="$(grep -arhoE 'kw:.*$' "$root"/global/index.md "$root"/topics/*/index.md 2>/dev/null \
        | sed 's/^kw://' | tr ',、' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
        | grep -av '^$' | sort -u || true)"
topic_names="$(list_dirs "$root/topics" || true)"

matched=0
while IFS= read -r k; do
  [ -n "$k" ] || continue
  case "$prompt" in *"$k"*) matched=1; break;; esac
done <<EOF
$kws
$topic_names
EOF

[ "$matched" -eq 1 ] || exit 0

ctx="[LLM Wiki] この質問は既存ナレッジに関連する可能性があります。回答前に $root/global/index.md と該当トピックの index.md を Read し、関連ページを参照して出典付きで答えること。"
emit "UserPromptSubmit" "$ctx"
