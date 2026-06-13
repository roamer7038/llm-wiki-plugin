#!/bin/bash
# Wiki ルートの絶対パスと初期化状態を返す（read-only）。stdin は読まない。
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

root="$(wiki_root)"
if wiki_exists; then
  printf 'root=%s\nexists=true\n' "$root"
else
  printf 'root=%s\nexists=false\n' "$root"
fi
