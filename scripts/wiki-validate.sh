#!/bin/bash
# Wiki 健全性チェック（read-only）。[scope] で範囲限定可。
# 検査: リンク切れ / 孤立ページ / index⇔ファイル / config⇔ディレクトリ /
#       必須 frontmatter / superseded_by 整合 / index 肥大化 / log 形式。
# レポートを出力し常に exit 0（セッションを止めない）。
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

wiki_exists || { echo "Wiki 未初期化"; exit 0; }
root="$(wiki_root)"
scope="${1:-}"

LLM_WIKI_ROOT="$root" LLM_WIKI_SCOPE="$scope" python3 <<'PY'
import os, re, glob
root=os.environ['LLM_WIKI_ROOT']; scope=os.environ.get('LLM_WIKI_SCOPE','')
INDEX_WARN=150

issues={'error':[], 'warn':[]}
def err(m): issues['error'].append(m)
def warn(m): issues['warn'].append(m)

def rel(p): return os.path.relpath(p, root)

# 対象 wiki ページ収集
base = os.path.join(root, scope) if scope else root
pages=[p for p in glob.glob(os.path.join(base,'**','wiki','**','*.md'), recursive=True)]
allpages=[p for p in glob.glob(os.path.join(root,'**','wiki','**','*.md'), recursive=True)]

def page_ref(p):
    # root/<scope>/wiki/<pt>/<slug>.md -> scope/pt/slug
    r=rel(p)[:-3]  # strip .md
    parts=r.split(os.sep)
    wi=parts.index('wiki')
    scope_='/'.join(parts[:wi]); pt=parts[wi+1]; slug=parts[wi+2] if len(parts)>wi+2 else parts[-1]
    return f"{scope_}/{pt}/{slug}", scope_, pt, slug

existing_refs={page_ref(p)[0] for p in allpages}

# 1) frontmatter 必須 + superseded_by
for p in pages:
    t=open(p,encoding='utf-8').read()
    fm=re.match(r'^---\n(.*?)\n---', t, re.S)
    body=t
    if not fm:
        err(f"frontmatter 無し: {rel(p)}"); continue
    head=fm.group(1)
    for key in ('title','page_type'):
        if not re.search(rf'^{key}:', head, re.M):
            err(f"必須 frontmatter 欠落[{key}]: {rel(p)}")
    m=re.search(r'^superseded_by:\s*(\S+)', head, re.M)
    if m:
        tgt=m.group(1).strip().strip('"').strip("'")
        if tgt and tgt not in existing_refs:
            err(f"superseded_by 先が存在しない[{tgt}]: {rel(p)}")

# 2) リンク切れ + inbound 収集（index.md は除外。孤立判定を歪めないため。
#    index のリンク健全性は §4 で別途検査する）
link_re=re.compile(r'\[\[([^\]]+)\]\]')
inbound={}  # ref -> count
for p in allpages + glob.glob(os.path.join(root,'**','overview.md'), recursive=True):
    t=open(p,encoding='utf-8').read()
    _, pscope, ppt, _ = (page_ref(p) if os.sep+'wiki'+os.sep in p else (None, None, None, None))
    for mt in link_re.finditer(t):
        tgt=mt.group(1).strip()
        if '/' in tgt:
            ref=tgt
        else:
            # 短縮形: 同一ディレクトリ前提
            if pscope is None:
                warn(f"短縮形リンク[{tgt}]を非ページから使用: {rel(p)}"); continue
            ref=f"{pscope}/{ppt}/{tgt}"
        inbound[ref]=inbound.get(ref,0)+1
        if ref not in existing_refs:
            err(f"リンク切れ[[{tgt}]]: {rel(p)}")

# 3) 孤立ページ（inbound 0）
for p in pages:
    ref=page_ref(p)[0]
    if inbound.get(ref,0)==0:
        warn(f"孤立ページ(inbound 0): {ref}")

# 4) index ⇔ ファイル
for ip in glob.glob(os.path.join(base if scope else root,'**','index.md'), recursive=True):
    t=open(ip,encoding='utf-8').read()
    n_entries=0
    for mt in link_re.finditer(t):
        n_entries+=1
        tgt=mt.group(1).strip()
        if tgt not in existing_refs:
            err(f"index が存在しないページを参照[{tgt}]: {rel(ip)}")
    if t.count('\n')>INDEX_WARN:
        warn(f"index 肥大化({t.count(chr(10))}行 > {INDEX_WARN}): {rel(ip)} 分割を検討")
# ページが自スコープ index に載っているか
for p in pages:
    ref, ps, pt, slug = page_ref(p)
    ip=os.path.join(root, ps, 'index.md')
    if os.path.exists(ip):
        if f"[[{ref}]]" not in open(ip,encoding='utf-8').read():
            warn(f"index 未掲載: {ref}")

# 5) config ⇔ ディレクトリ（best-effort: name: トークンの存在確認）
cfg=os.path.join(root,'config.yml')
if os.path.exists(cfg):
    cfg_lines=[l for l in open(cfg,encoding='utf-8').read().split('\n') if not l.lstrip().startswith('#')]
    names=re.findall(r'name:\s*([A-Za-z0-9_\-]+)', '\n'.join(cfg_lines))
    wiki_dirs={os.path.basename(d) for d in glob.glob(os.path.join(root,'global','wiki','*'))}
    topic_dirs={os.path.basename(d) for d in glob.glob(os.path.join(root,'topics','*')) if os.path.isdir(d)}
    known=wiki_dirs|topic_dirs
    for n in names:
        if n not in known:
            warn(f"config に記載があるが対応ディレクトリが無い: {n}")
    for d in wiki_dirs:
        if d not in names:
            warn(f"global/wiki に {d}/ があるが config 未記載")

# 6) log 形式
logf=os.path.join(root,'log.md')
if os.path.exists(logf):
    for i,l in enumerate(open(logf,encoding='utf-8'),1):
        if l.startswith('## ') and not re.match(r'## \[\d{4}-\d{2}-\d{2}( \d{2}:\d{2})?\] \w+ \| .+ \| ', l):
            warn(f"log 形式不正(L{i}): {l.strip()}")

print(f"# wiki-validate{(' — '+scope) if scope else ''}")
print(f"\nERROR: {len(issues['error'])}  WARN: {len(issues['warn'])}\n")
for m in issues['error']: print(f"  [ERROR] {m}")
for m in issues['warn']: print(f"  [WARN ] {m}")
if not issues['error'] and not issues['warn']:
    print("  問題は検出されませんでした。")
PY
