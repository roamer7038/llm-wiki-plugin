#!/bin/bash
# リンクグラフ全体を出力・分析する（read-only）。
# usage: wiki-graph.sh [--summary|--json|--dot] [scope]
#   既定 --summary。scope 指定でノードを当該スコープのページに限定（エッジは全体から収集）。
# ノード = 全 wiki ページ（ref: scope/wiki/page_type/slug）。
# エッジ = ページ本文の outbound [[...]]（短縮形は同一ディレクトリで解決）。index.md は集計対象外。
# 分析: 連結成分（=島）／孤立ページ（次数0）／被リンク上位ハブ／リンク切れ。
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

fmt=summary; scope=""
for a in "$@"; do
  case "$a" in
    --summary) fmt=summary;; --json) fmt=json;; --dot) fmt=dot;;
    --*) echo "usage: wiki-graph.sh [--summary|--json|--dot] [scope]" >&2; exit 2;;
    *) scope="$a";;
  esac
done
wiki_exists || { echo "Wiki 未初期化"; exit 0; }

LLM_WIKI_ROOT="$(wiki_root)" LLM_WIKI_FMT="$fmt" LLM_WIKI_SCOPE="$scope" python3 <<'PY'
import os, re, glob, json
root=os.environ['LLM_WIKI_ROOT']; fmt=os.environ['LLM_WIKI_FMT']
scope=os.environ.get('LLM_WIKI_SCOPE','')

def rel(p): return os.path.relpath(p, root)
def page_ref(p):
    pr=rel(p)[:-3].split(os.sep); wi=pr.index('wiki')
    return f"{'/'.join(pr[:wi])}/wiki/{pr[wi+1]}/{pr[wi+2]}", '/'.join(pr[:wi]), pr[wi+1]
def resolve(tgt, pscope, ppt):
    return tgt if '/' in tgt else f"{pscope}/wiki/{ppt}/{tgt}"

link_re=re.compile(r'\[\[([^\]]+)\]\]')
allpages=glob.glob(os.path.join(root,'**','wiki','**','*.md'), recursive=True)
existing={page_ref(p)[0] for p in allpages}

# ノード集合（scope 指定時は当該スコープ配下のページに限定）
nodes={r for r in existing if (not scope or r.startswith(scope+'/'))}

edges=[]            # (src, dst) 実在先のみ
broken=[]           # (src, raw) リンク切れ
outdeg={}; indeg={}
adj={r:set() for r in nodes}   # 無向（連結成分用）
for p in allpages:
    src, ps, ppt = page_ref(p)
    if src not in nodes: continue
    seen=set()
    for mt in link_re.finditer(open(p,encoding='utf-8').read()):
        raw=mt.group(1).strip()
        if '<' in raw or '>' in raw: continue
        dst=resolve(raw, ps, ppt)
        if dst==src or dst in seen: continue
        seen.add(dst)
        if dst not in existing:
            broken.append((src, raw)); continue
        edges.append((src,dst))
        outdeg[src]=outdeg.get(src,0)+1
        indeg[dst]=indeg.get(dst,0)+1
        if dst in adj:                 # scope 限定時、対象外ノードは無向グラフから除外
            adj[src].add(dst); adj[dst].add(src)

# 連結成分（島）
seen=set(); comps=[]
for n in nodes:
    if n in seen: continue
    stack=[n]; comp=[]
    while stack:
        x=stack.pop()
        if x in seen: continue
        seen.add(x); comp.append(x)
        stack.extend(adj.get(x,()))
    comps.append(sorted(comp))
comps.sort(key=len, reverse=True)
isolated=sorted(n for n in nodes if not adj.get(n))

if fmt=='json':
    print(json.dumps({
        'nodes': sorted(nodes),
        'edges': [list(e) for e in edges],
        'broken': [list(b) for b in broken],
        'components': comps,
        'isolated': isolated,
    }, ensure_ascii=False, indent=2))
elif fmt=='dot':
    print('digraph wiki {')
    print('  rankdir=LR; node [shape=box, fontsize=10];')
    for s,d in edges:
        print(f'  "{s}" -> "{d}";')
    for n in isolated:
        print(f'  "{n}" [color=red];')
    print('}')
else:
    title = f"# wiki-graph{(' — '+scope) if scope else ''}"
    print(title)
    print(f"\nノード {len(nodes)} / エッジ {len(edges)} / リンク切れ {len(broken)}")
    print(f"連結成分（島）: {len(comps)}  最大 {len(comps[0]) if comps else 0} ノード")
    if len(comps)>1:
        print("\n## 島（連結成分・小さい順に注意）")
        for c in comps:
            head=c[0]
            print(f"  [{len(c)}] {head}" + (f"  …他{len(c)-1}" if len(c)>1 else "  (孤立)"))
    print("\n## 被リンク上位（ハブ）")
    for ref,d in sorted(indeg.items(), key=lambda kv:kv[1], reverse=True)[:10]:
        print(f"  {d:3d} <- {ref}")
    if isolated:
        print("\n## 孤立ページ（in/out とも 0）")
        for n in isolated: print(f"  {n}")
    if broken:
        print("\n## リンク切れ")
        for s,r in broken: print(f"  {s} -> [[{r}]]")
PY
