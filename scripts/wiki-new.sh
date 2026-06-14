#!/bin/bash
# 新規ページの雛形を所定の場所に作成する（write, flock）。
# ユーザ起点の手動ナレッジ追加（/wiki-new）の決定論部分。
# usage: wiki-new.sh <scope> <page_type> <title> [summary] [kw ...]
#   scope: global | topics/<topic>
#   summary を渡すと index も upsert する（省略時はページ作成のみ）。
# slug は決定論生成。テンプレを配置し frontmatter(title/page_type/scope/created/updated)
# と H1 を埋める。既存ページがあれば上書きせずエラー（重複判断は呼び出し側）。
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

scope="${1:-}"; ptype="${2:-}"; title="${3:-}"
[ -n "$scope" ] && [ -n "$ptype" ] && [ -n "$title" ] || {
  echo "usage: wiki-new.sh <scope> <page_type> <title> [summary] [kw ...]" >&2; exit 2; }
shift 3 || true
summary="${1:-}"; [ "$#" -gt 0 ] && shift || true
kw="$(printf '%s' "${*:-}")"
wiki_exists || { echo "Wiki 未初期化" >&2; exit 2; }
root="$(wiki_root)"
slug="$(slugify "$title")"
template="$(wiki_templates_dir)/$ptype.md"

acquire_write_lock

LLM_WIKI_ROOT="$root" LLM_WIKI_SCOPE="$scope" LLM_WIKI_PT="$ptype" \
LLM_WIKI_TITLE="$title" LLM_WIKI_SLUG="$slug" LLM_WIKI_TEMPLATE="$template" \
LLM_WIKI_SUMMARY="$summary" LLM_WIKI_KW="$kw" python3 <<'PY'
import os, re, datetime, sys
root=os.environ['LLM_WIKI_ROOT']; scope=os.environ['LLM_WIKI_SCOPE']
pt=os.environ['LLM_WIKI_PT']; title=os.environ['LLM_WIKI_TITLE']
slug=os.environ['LLM_WIKI_SLUG']; template=os.environ['LLM_WIKI_TEMPLATE']
summary=os.environ['LLM_WIKI_SUMMARY']; kw=os.environ['LLM_WIKI_KW']
today=datetime.date.today().isoformat()

target=os.path.join(root, scope, 'wiki', pt, slug+'.md')
if os.path.exists(target):
    sys.exit(f"既に存在します（更新は wiki-index-upsert / 直接編集で）: {scope}/{pt}/{slug}")
os.makedirs(os.path.dirname(target), exist_ok=True)

# テンプレ取得（無ければ最小汎用テンプレ）
if os.path.exists(template):
    t=open(template,encoding='utf-8').read()
else:
    t=("---\ntitle: <title>\naliases: []\npage_type: <pt>\nscope: <scope>\n"
       "created: <YYYY-MM-DD>\nupdated: <YYYY-MM-DD>\ntags: []\n---\n\n"
       "# <title>\n\n<本文をここに記述>\n")

# frontmatter を埋める（キーがあれば値を差し替え、無ければ追加はしない）
def set_fm(t, key, val):
    pat=re.compile(rf'^({re.escape(key)}:\s*).*$', re.M)
    return pat.sub(rf'\g<1>{val}', t, count=1) if pat.search(t) else t
t=set_fm(t,'title',title); t=set_fm(t,'page_type',pt); t=set_fm(t,'scope',scope)
t=set_fm(t,'created',today); t=set_fm(t,'updated',today)
# 最初の H1 をタイトルに
t=re.sub(r'^#\s+.*$', f'# {title}', t, count=1, flags=re.M)
open(target,'w',encoding='utf-8').write(t)

# summary 指定時は index を upsert（ロック保持中のため inline 実装）
if summary.strip():
    idx=os.path.join(root, scope, 'index.md')
    link=f"[[{scope}/wiki/{pt}/{slug}]]"
    line=f"- {link} — {summary.strip()}" + (f" | kw: {kw.strip()}" if kw.strip() else "")
    lines=open(idx,encoding='utf-8').read().split('\n') if os.path.exists(idx) else [f"# Index — {scope}",""]
    header=f"## {pt}"; hi=None
    for i,l in enumerate(lines):
        if l.strip()==header: hi=i; break
    if hi is None:
        if lines and lines[-1].strip()!='': lines.append('')
        lines += [header, line, '']
    else:
        j=hi+1
        while j<len(lines) and not lines[j].startswith('## '): j+=1
        ins=j
        while ins>hi+1 and lines[ins-1].strip()=='': ins-=1
        lines.insert(ins, line)
    os.makedirs(os.path.dirname(idx), exist_ok=True)
    open(idx,'w',encoding='utf-8').write('\n'.join(lines))

print(target)
PY

# log（ロック保持中のため直接追記）
printf '## [%s] new | %s | %s\n- 手動ページ作成: %s/%s\n\n' \
  "$(date '+%F %H:%M')" "$scope" "$title" "$ptype" "$slug" >> "$root/log.md"
