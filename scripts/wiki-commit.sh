#!/bin/bash
# Stop フック本体: そのターンに生じた Wiki の変更を 1 コミットにまとめる（write）。
# 1 回の論理作業（ingest 等が内部で起こす複数 write）を 1 コミットに束ねる。
# git 無効／未初期化／変更なしは静かに no-op。Stop をブロックしない（常に exit 0）。
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

commit_wiki() {
  set -euo pipefail

  wiki_exists || return 0
  git_enabled || return 0

  acquire_write_lock
  wiki_git_init

  # 変更が無ければ何もしない（毎ターン発火しても git 履歴を汚さない）
  # 既知の Wiki 構造のみをステージ（想定外のルート直下ファイルは巻き込まない）
  wiki_git_add_scoped
  if wiki_git diff --cached --quiet; then return 0; fi

  # コミットメッセージは log.md にこのターン増えた見出し行から導出する。
  root="$(wiki_root)"
  if wiki_git rev-parse --verify -q HEAD >/dev/null 2>&1; then
    newheads="$(wiki_git diff HEAD -- log.md 2>/dev/null \
      | grep -E '^\+## \[' | sed -E 's/^\+## \[[0-9: -]*\] //' || true)"
  else
    newheads="$(grep -E '^## \[' "$root/log.md" 2>/dev/null \
      | sed -E 's/^## \[[0-9: -]*\] //' || true)"
  fi

  n="$(printf '%s' "$newheads" | grep -c . || true)"
  if [ "${n:-0}" -ge 1 ]; then
    first="$(printf '%s\n' "$newheads" | head -n1)"
    if [ "$n" -gt 1 ]; then msg="$first (+$((n-1)))"; else msg="$first"; fi
  else
    msg="edit | manual | $(date '+%F %H:%M')"
  fi

  wiki_git commit -q -m "$msg"
}

commit_wiki || true
exit 0
