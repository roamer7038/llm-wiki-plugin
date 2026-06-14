#!/bin/bash
# ページのリンク関係を追う（read-only）。グラフ構造のナビ・リネーム影響確認に使う。
# usage: wiki-links.sh <ref> [--inbound|--outbound]
#   ref 形式: <scope>/<page_type>/<slug>  （scope は global または topics/<topic>）
#   既定（オプション無し）は inbound/outbound 両方を表示。
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

ref="${1:-}"; mode="${2:-both}"
[ -n "$ref" ] || { echo "usage: wiki-links.sh <ref> [--inbound|--outbound]" >&2; exit 2; }
case "$mode" in --inbound) mode=inbound;; --outbound) mode=outbound;; both|"") mode=both;; *)
  echo "usage: wiki-links.sh <ref> [--inbound|--outbound]" >&2; exit 2;; esac
wiki_exists || { echo "Wiki 未初期化"; exit 0; }

LLM_WIKI_ROOT="$(wiki_root)" LLM_WIKI_REF="$ref" LLM_WIKI_MODE="$mode" python3 <<'PY'
import os, re, glob
root=os.environ['LLM_WIKI_ROOT']
ref=os.environ['LLM_WIKI_REF'].strip('/')
mode=os.environ['LLM_WIKI_MODE']

parts=[p for p in ref.split('/') if p]
# 新形式 scope/wiki/pt/slug を基準に解析。旧形式 scope/pt/slug も受理（wiki を補う）。
if 'wiki' in parts:
    wi=parts.index('wiki'); scope='/'.join(parts[:wi]); pt=parts[wi+1]; slug=parts[wi+2]
elif len(parts)>=3:
    slug=parts[-1]; pt=parts[-2]; scope='/'.join(parts[:-2])
else:
    raise SystemExit(f"ref 形式が不正: {ref} (期待: scope/wiki/page_type/slug)")
target=f"{scope}/wiki/{pt}/{slug}"
tfile=os.path.join(root, scope, 'wiki', pt, slug+'.md')

link_re=re.compile(r'\[\[([^\]]+)\]\]')
def rel(p): return os.path.relpath(p, root)

def page_ref(p):
    r=rel(p)[:-3]; pr=r.split(os.sep); wi=pr.index('wiki')
    return f"{'/'.join(pr[:wi])}/wiki/{pr[wi+1]}/{pr[wi+2]}", '/'.join(pr[:wi]), pr[wi+1]

def resolve(tgt, pscope, ppt):
    # 絶対形はそのまま。短縮形は同一ディレクトリ前提で補完。
    return tgt if '/' in tgt else (f"{pscope}/wiki/{ppt}/{tgt}" if pscope else tgt)

allpages=glob.glob(os.path.join(root,'**','wiki','**','*.md'), recursive=True)
existing={page_ref(p)[0] for p in allpages}

print(f"# links: {target}" + ("" if os.path.exists(tfile) else "  (※ ページ実体なし)"))

if mode in ('outbound','both'):
    print("\n## outbound（このページが張るリンク）")
    if os.path.exists(tfile):
        seen=[]
        for mt in link_re.finditer(open(tfile,encoding='utf-8').read()):
            r=resolve(mt.group(1).strip(), scope, pt)
            if r in seen: continue
            seen.append(r)
            mark="" if r in existing else "  [リンク切れ]"
            print(f"  -> {r}{mark}")
        if not seen: print("  (なし)")
    else:
        print("  (ページ実体が無いため取得不可)")

if mode in ('inbound','both'):
    print("\n## inbound（このページを指すリンク）")
    hits={}
    # wiki ページ＋ overview を走査（index.md はカタログなので別表示）
    srcs=allpages+glob.glob(os.path.join(root,'**','overview.md'), recursive=True)
    for p in srcs:
        is_page = 'wiki' in rel(p).split(os.sep)
        if is_page:
            sref, ps, ppt = page_ref(p)
        else:
            sref, ps, ppt = None, None, None
        for mt in link_re.finditer(open(p,encoding='utf-8').read()):
            if resolve(mt.group(1).strip(), ps, ppt)==target:
                hits[rel(p)] = sref
                break
    for path in sorted(hits):
        print(f"  <- {hits[path] or path}")
    if not hits: print("  (なし＝孤立)")
    # index 掲載状況
    idx=os.path.join(root, scope, 'index.md')
    listed = os.path.exists(idx) and f"[[{target}]]" in open(idx,encoding='utf-8').read()
    print(f"\n  index 掲載: {'あり' if listed else 'なし'}  ({scope}/index.md)")
PY
