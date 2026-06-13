#!/bin/bash
# index.md のエントリを追加/更新（write, flock）。
# usage: wiki-index-upsert.sh <scope> <page_type> <slug> <summary> [kw ...]
#   scope: global | topics/<topic>
# 同一 [[link]] の行があれば置換、無ければ該当 ## <page_type> 節に追加（節が無ければ作る）。
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

scope="${1:-}"; ptype="${2:-}"; slug="${3:-}"; summary="${4:-}"
[ -n "$scope" ] && [ -n "$ptype" ] && [ -n "$slug" ] || {
  echo "usage: wiki-index-upsert.sh <scope> <page_type> <slug> <summary> [kw ...]" >&2; exit 2; }
shift 4 || true
kw="$(printf '%s' "${*:-}")"

wiki_exists || { echo "Wiki 未初期化" >&2; exit 2; }
root="$(wiki_root)"
idx="$root/$scope/index.md"

acquire_write_lock

LLM_WIKI_IDX="$idx" LLM_WIKI_SCOPE="$scope" LLM_WIKI_PT="$ptype" \
LLM_WIKI_SLUG="$slug" LLM_WIKI_SUMMARY="$summary" LLM_WIKI_KW="$kw" \
python3 <<'PY'
import os, io
idx=os.environ['LLM_WIKI_IDX']; scope=os.environ['LLM_WIKI_SCOPE']
pt=os.environ['LLM_WIKI_PT']; slug=os.environ['LLM_WIKI_SLUG']
summary=os.environ['LLM_WIKI_SUMMARY']; kw=os.environ['LLM_WIKI_KW']

os.makedirs(os.path.dirname(idx), exist_ok=True)
link=f"[[{scope}/{pt}/{slug}]]"
line=f"- {link} — {summary}"
if kw.strip():
    line += f" | kw: {kw.strip()}"

if os.path.exists(idx):
    lines=open(idx, encoding='utf-8').read().split('\n')
else:
    lines=[f"# Index — {scope}", ""]

# 既存の同一リンク行を探して置換
for i,l in enumerate(lines):
    if link in l and l.lstrip().startswith('- '):
        lines[i]=line
        open(idx,'w',encoding='utf-8').write('\n'.join(lines))
        print(f"index 更新: {scope}/{pt}/{slug}")
        raise SystemExit(0)

# 節 "## <pt>" を探す
header=f"## {pt}"
hi=None
for i,l in enumerate(lines):
    if l.strip()==header:
        hi=i; break

if hi is None:
    # 節が無ければ末尾に追加
    if lines and lines[-1].strip()!='':
        lines.append('')
    lines.append(header)
    lines.append(line)
    lines.append('')
else:
    # 節の末尾（次の見出し直前 or ファイル末尾）に挿入
    j=hi+1
    while j<len(lines) and not lines[j].startswith('## '):
        j+=1
    insert=j
    while insert>hi+1 and lines[insert-1].strip()=='':
        insert-=1
    lines.insert(insert, line)

open(idx,'w',encoding='utf-8').write('\n'.join(lines))
print(f"index 追加: {scope}/{pt}/{slug}")
PY
