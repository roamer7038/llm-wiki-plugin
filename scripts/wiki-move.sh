#!/bin/bash
# ページの move/rename ＋ inbound リンク書換え ＋ index 更新 ＋ log（write, flock）。
# usage: wiki-move.sh <from-ref> <to-ref>
#   ref 形式: <scope>/<page_type>/<slug>  （scope は global または topics/<topic>）
#   例: wiki-move.sh global/concepts/attention topics/ml/concepts/attention
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

from="${1:-}"; to="${2:-}"
[ -n "$from" ] && [ -n "$to" ] || { echo "usage: wiki-move.sh <from-ref> <to-ref>" >&2; exit 2; }
wiki_exists || { echo "Wiki 未初期化" >&2; exit 2; }
root="$(wiki_root)"

acquire_write_lock

LLM_WIKI_ROOT="$root" LLM_WIKI_FROM="$from" LLM_WIKI_TO="$to" python3 <<'PY'
import os, re, sys, glob, datetime
root=os.environ['LLM_WIKI_ROOT']
fr=os.environ['LLM_WIKI_FROM'].strip('/'); to=os.environ['LLM_WIKI_TO'].strip('/')

def split_ref(ref):
    # 新形式 scope/wiki/pt/slug を基準。旧形式 scope/pt/slug も受理。返す scope は wiki を含まない。
    parts=[p for p in ref.split('/') if p]
    if 'wiki' in parts:
        wi=parts.index('wiki'); return '/'.join(parts[:wi]), parts[wi+1], parts[wi+2]
    if len(parts)<3:
        sys.exit(f"ref 形式が不正: {ref} (期待: scope/wiki/page_type/slug)")
    return '/'.join(parts[:-2]), parts[-2], parts[-1]

fs, fpt, fslug = split_ref(fr)
ts, tpt, tslug = split_ref(to)
ffile=os.path.join(root, fs, 'wiki', fpt, fslug+'.md')
tfile=os.path.join(root, ts, 'wiki', tpt, tslug+'.md')

if not os.path.exists(ffile):
    sys.exit(f"移動元が存在しません: {ffile}")
if os.path.exists(tfile):
    sys.exit(f"移動先が既に存在します: {tfile}")

os.makedirs(os.path.dirname(tfile), exist_ok=True)

# 本文を読み frontmatter の scope/page_type/updated を更新
text=open(ffile, encoding='utf-8').read()
today=datetime.date.today().isoformat()
def set_fm(t, key, val):
    pat=re.compile(rf'^({re.escape(key)}:\s*).*$', re.M)
    if pat.search(t):
        return pat.sub(rf'\g<1>{val}', t, count=1)
    return t
text=set_fm(text,'scope',ts)
text=set_fm(text,'page_type',tpt)
text=set_fm(text,'updated',today)
open(tfile,'w',encoding='utf-8').write(text)
os.remove(ffile)

# inbound リンク書換え: 絶対形 [[fs/fpt/fslug]] -> [[ts/tpt/tslug]]
abs_from=f"[[{fs}/wiki/{fpt}/{fslug}]]"
abs_to=f"[[{ts}/wiki/{tpt}/{tslug}]]"
# 移動元と同一ディレクトリ内の短縮形 [[fslug]] も対象（書換え後は絶対形へ正規化）
short_from=f"[[{fslug}]]"
from_dir=os.path.join(root, fs, 'wiki', fpt)

rewrote=0
for path in glob.glob(os.path.join(root,'**','*.md'), recursive=True):
    # index.md は後段の index 更新ロジックが専管するため除外
    if os.path.basename(path)=='index.md':
        continue
    c=open(path,encoding='utf-8').read(); orig=c
    c=c.replace(abs_from, abs_to)
    if os.path.dirname(path)==from_dir:
        c=c.replace(short_from, abs_to)
    if c!=orig:
        open(path,'w',encoding='utf-8').write(c); rewrote+=1

# index: 旧スコープから当該行を除去し、要約/kw を回収
def index_path(scope): return os.path.join(root, scope, 'index.md')
old_link=f"[[{fs}/wiki/{fpt}/{fslug}]]"
summary=""; kw=""
ip=index_path(fs)
if os.path.exists(ip):
    lines=open(ip,encoding='utf-8').read().split('\n'); keep=[]
    for l in lines:
        if old_link in l and l.lstrip().startswith('- '):
            m=re.search(r'—\s*(.*)$', l)
            if m:
                rest=m.group(1)
                if '| kw:' in rest:
                    summary, kw = rest.split('| kw:',1)
                    summary=summary.strip(); kw=kw.strip()
                else:
                    summary=rest.strip()
            continue
        keep.append(l)
    open(ip,'w',encoding='utf-8').write('\n'.join(keep))

if not summary:
    m=re.search(r'^title:\s*(.*)$', text, re.M)
    summary=m.group(1).strip() if m else tslug

# index: 新スコープへ追加（節を作り末尾挿入）
ip2=index_path(ts)
new_link=f"[[{ts}/wiki/{tpt}/{tslug}]]"
new_line=f"- {new_link} — {summary}" + (f" | kw: {kw}" if kw else "")
if os.path.exists(ip2):
    lines=open(ip2,encoding='utf-8').read().split('\n')
else:
    lines=[f"# Index — {ts}", ""]
hdr=f"## {tpt}"; hi=None
for i,l in enumerate(lines):
    if l.strip()==hdr: hi=i; break
if hi is None:
    if lines and lines[-1].strip()!='': lines.append('')
    lines += [hdr, new_line, '']
else:
    j=hi+1
    while j<len(lines) and not lines[j].startswith('## '): j+=1
    ins=j
    while ins>hi+1 and lines[ins-1].strip()=='': ins-=1
    lines.insert(ins, new_line)
open(ip2,'w',encoding='utf-8').write('\n'.join(lines))

print(f"move: {fr} -> {to}  (inbound 書換え {rewrote} ファイル)")
PY

# log（ロック保持中のため wiki-log.sh は呼ばず直接追記）
printf '## [%s] move | %s | %s\n- %s -> %s\n\n' \
  "$(date '+%F %H:%M')" "$(printf '%s' "$from" | cut -d/ -f1)" "$from" "$from" "$to" \
  >> "$root/log.md"
