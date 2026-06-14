#!/bin/bash
# トピックをサブツリーごとリネームする（write, flock）。
# wiki-move のリンク書換えをトピック単位に一般化したもの。
# usage: wiki-rename-topic.sh <old> <new>
#   <old> <new> はトピック名（topics/ 配下のディレクトリ名）。
#   例: wiki-rename-topic.sh ml machine-learning
# 処理: ディレクトリ mv ＋ 配下全ページの scope 更新 ＋ 全 wiki の
#       [[topics/<old>/...]] 一括書換え ＋ config.yml の topics 名更新 ＋ log。
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

old="${1:-}"; new="${2:-}"
[ -n "$old" ] && [ -n "$new" ] || { echo "usage: wiki-rename-topic.sh <old> <new>" >&2; exit 2; }
# スラッシュを含む値は誤用（トピック名のみ受ける）
case "$old$new" in */*) echo "トピック名のみ指定してください（scope や / は不可）: $old -> $new" >&2; exit 2;; esac
wiki_exists || { echo "Wiki 未初期化" >&2; exit 2; }
root="$(wiki_root)"

acquire_write_lock

LLM_WIKI_ROOT="$root" LLM_WIKI_OLD="$old" LLM_WIKI_NEW="$new" python3 <<'PY'
import os, re, sys, glob, datetime
root=os.environ['LLM_WIKI_ROOT']; old=os.environ['LLM_WIKI_OLD']; new=os.environ['LLM_WIKI_NEW']

old_dir=os.path.join(root,'topics',old)
new_dir=os.path.join(root,'topics',new)
if not os.path.isdir(old_dir): sys.exit(f"移動元トピックが存在しません: topics/{old}")
if os.path.exists(new_dir):   sys.exit(f"移動先トピックが既に存在します: topics/{new}")

# 1) ディレクトリをまるごと改名
os.rename(old_dir, new_dir)

old_scope=f"topics/{old}"; new_scope=f"topics/{new}"

# 2) 配下全ページの frontmatter scope を更新
for p in glob.glob(os.path.join(new_dir,'**','*.md'), recursive=True):
    t=open(p,encoding='utf-8').read()
    nt=re.sub(r'^(scope:\s*).*$', rf'\g<1>{new_scope}', t, count=1, flags=re.M)
    if nt!=t: open(p,'w',encoding='utf-8').write(nt)

# 3) 全 wiki の [[topics/<old>/...]] -> [[topics/<new>/...]] を一括書換え（index 含む）
rewrote=0
pat=re.compile(r'(\[\[)'+re.escape(old_scope)+r'/')
for p in glob.glob(os.path.join(root,'**','*.md'), recursive=True):
    c=open(p,encoding='utf-8').read()
    nc=pat.sub(rf'\g<1>{new_scope}/', c)
    if nc!=c: open(p,'w',encoding='utf-8').write(nc); rewrote+=1

# 4) 配下 index.md / overview.md の見出し "— topics/<old>" 等の表記も更新
for name in ('index.md','overview.md'):
    fp=os.path.join(new_dir,name)
    if os.path.exists(fp):
        c=open(fp,encoding='utf-8').read()
        c=c.replace(old_scope, new_scope)
        open(fp,'w',encoding='utf-8').write(c)

# 5) config.yml の topics: エントリ名を更新（page_types は触らない）
cfg=os.path.join(root,'config.yml')
if os.path.exists(cfg):
    lines=open(cfg,encoding='utf-8').read().split('\n')
    in_topics=False; changed=False
    for i,l in enumerate(lines):
        if re.match(r'^topics:', l): in_topics=True; continue
        if in_topics and re.match(r'^\S', l): in_topics=False  # 別トップレベルキー
        if in_topics:
            nl=re.sub(r'(\{\s*name:\s*)'+re.escape(old)+r'(\b)', rf'\g<1>{new}\g<2>', l)
            if nl!=l: lines[i]=nl; changed=True
    if changed: open(cfg,'w',encoding='utf-8').write('\n'.join(lines))

print(f"rename-topic: topics/{old} -> topics/{new}  (リンク書換え {rewrote} ファイル)")
PY

# log（ロック保持中のため直接追記）
printf '## [%s] move | topics/%s | トピック改名: %s -> %s\n- topics/%s をサブツリーごと改名し inbound リンク・config を更新\n\n' \
  "$(date '+%F %H:%M')" "$new" "$old" "$new" "$old" >> "$root/log.md"
