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

# 実在する index.md をエントリ件数つきで列挙（知識の所在を LLM に明示する）。
# 例示の global/index.md は空のことがあるため、件数で実体のあるスコープを示す。
index_catalog() {
  local f n
  for f in "$root/global/index.md" "$root"/topics/*/index.md; do
    [ -f "$f" ] || continue
    n="$(grep -cE '^\- \[\[' "$f" 2>/dev/null || true)"
    printf '  - %s （%s 件）\n' "$f" "$n"
  done
}
index_list="$(index_catalog || true)"
[ -n "$index_list" ] || index_list="  （index 未作成）"

if [ "$mode" = "session" ]; then
  ctx="[LLM Wiki] $root にナレッジベースがあります。
トピック: $topics
ページ種別: $ptypes
知識・事実・調査を要する質問に答える前に、関連スコープの index.md を Read し、関連ページを辿ってから出典付きで回答すること。index は次にある（件数 0 は実体が薄い／未整備）:
$index_list
リンクは [[scope/wiki/page_type/slug]] 形式でファイルパスに一致する（例: $root/topics/<topic>/wiki/concepts/<slug>.md）。index から関連ページへ辿れる。
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
# 区切り（半角/全角コンマ）での分割は python で行う。tr はバイト処理で多バイト
# 文字（全角コンマ・日本語語彙）を寸断し壊すため使わない。
kws="$(grep -arhoE 'kw:.*$' "$root"/global/index.md "$root"/topics/*/index.md 2>/dev/null \
        | sed 's/^kw://' \
        | python3 -c 'import sys,re
for line in sys.stdin:
    for w in re.split("[,、]", line):
        w = w.strip()
        if w: print(w)' \
        | sort -u || true)"
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
