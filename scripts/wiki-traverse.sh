#!/bin/bash
# 起点ページからリンクを N ホップ辿って近傍ページ群を集める（read-only）。
# 「グラフを辿って関連ドキュメントを追う」簡易クエリ。回答前の文脈収集に使う。
# usage: wiki-traverse.sh <ref> [--depth N] [--outbound|--inbound|--both]
#   ref: scope/wiki/page_type/slug（旧 scope/page_type/slug も受理）
#   既定 depth=2, --both。各到達ページは index.md の一行要約つきで深さ別に表示。
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

ref="${1:-}"; shift || true
[ -n "$ref" ] || { echo "usage: wiki-traverse.sh <ref> [--depth N] [--outbound|--inbound|--both]" >&2; exit 2; }
depth=2; dir=both
while [ "$#" -gt 0 ]; do
  case "$1" in
    --depth) depth="${2:-2}"; shift 2;;
    --outbound) dir=outbound; shift;; --inbound) dir=inbound; shift;; --both) dir=both; shift;;
    *) echo "不明な引数: $1" >&2; exit 2;;
  esac
done
wiki_exists || { echo "Wiki 未初期化"; exit 0; }

LLM_WIKI_ROOT="$(wiki_root)" LLM_WIKI_REF="$ref" LLM_WIKI_DEPTH="$depth" LLM_WIKI_DIR="$dir" python3 <<'PY'
import os, re, glob
from collections import deque, defaultdict
root=os.environ['LLM_WIKI_ROOT']
ref=os.environ['LLM_WIKI_REF'].strip('/'); depth=int(os.environ['LLM_WIKI_DEPTH']); dir=os.environ['LLM_WIKI_DIR']

def rel(p): return os.path.relpath(p, root)
def page_ref(p):
    pr=rel(p)[:-3].split(os.sep); wi=pr.index('wiki')
    return f"{'/'.join(pr[:wi])}/wiki/{pr[wi+1]}/{pr[wi+2]}", '/'.join(pr[:wi]), pr[wi+1]
def resolve(tgt, pscope, ppt):
    return tgt if '/' in tgt else f"{pscope}/wiki/{ppt}/{tgt}"

# 起点 ref を正規化（wiki セグメントが無ければ補う）
parts=[p for p in ref.split('/') if p]
if 'wiki' in parts:
    start=ref
else:
    wi=len(parts)-2
    start=f"{'/'.join(parts[:-2])}/wiki/{parts[-2]}/{parts[-1]}"

link_re=re.compile(r'\[\[([^\]]+)\]\]')
allpages=glob.glob(os.path.join(root,'**','wiki','**','*.md'), recursive=True)
existing={page_ref(p)[0] for p in allpages}

# 隣接（forward=outbound, back=inbound）
fwd=defaultdict(set); back=defaultdict(set)
for p in allpages:
    src, ps, ppt = page_ref(p)
    for mt in link_re.finditer(open(p,encoding='utf-8').read()):
        raw=mt.group(1).strip()
        if '<' in raw or '>' in raw: continue
        dst=resolve(raw, ps, ppt)
        if dst in existing and dst!=src:
            fwd[src].add(dst); back[dst].add(src)

# index.md から ref -> 一行要約 を収集
summ={}
for ip in glob.glob(os.path.join(root,'**','index.md'), recursive=True):
    for l in open(ip,encoding='utf-8'):
        m=re.match(r'^\-\s*\[\[([^\]]+)\]\]\s*—\s*(.*)$', l)
        if m:
            s=m.group(2).split('| kw:')[0].strip()
            summ[m.group(1).strip()]=s

if start not in existing:
    print(f"# traverse: {start}\n\n起点ページが存在しません。"); raise SystemExit(0)

# BFS（深さ記録）
adj=lambda n: (fwd[n]|back[n]) if dir=='both' else (fwd[n] if dir=='outbound' else back[n])
level={start:0}; q=deque([start])
while q:
    n=q.popleft()
    if level[n]>=depth: continue
    for m in sorted(adj(n)):
        if m not in level:
            level[m]=level[n]+1; q.append(m)

by_depth=defaultdict(list)
for n,d in level.items(): by_depth[d].append(n)

print(f"# traverse: {start}  (depth={depth}, {dir})")
print(f"到達 {len(level)} ページ\n")
for d in range(depth+1):
    if d not in by_depth: continue
    print(f"## hop {d}")
    for n in sorted(by_depth[d]):
        s=summ.get(n,'')
        print(f"  {n}" + (f" — {s}" if s else ""))
    print()
PY
