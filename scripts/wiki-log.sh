#!/bin/bash
# log.md へ 1 エントリを flock 付きで append（write）。
# usage: wiki-log.sh <op> <scope> <title> [bullet ...]
#   op: init|ingest|query|lint|topic|move
#   bullet: 箇条書き各行（任意・複数可、引数で渡す）。
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

op="${1:-}"; scope="${2:-}"; title="${3:-}"
[ -n "$op" ] && [ -n "$scope" ] && [ -n "$title" ] || {
  echo "usage: wiki-log.sh <op> <scope> <title> [bullet ...]" >&2; exit 2; }
shift 3
bullets=("$@")

wiki_exists || { echo "Wiki 未初期化" >&2; exit 2; }
root="$(wiki_root)"

acquire_write_lock
{
  printf '## [%s] %s | %s | %s\n' "$(date '+%F %H:%M')" "$op" "$scope" "$title"
  for b in "${bullets[@]:-}"; do [ -n "$b" ] && printf -- '- %s\n' "$b"; done
  printf '\n'
} >> "$root/log.md"

echo "log 追記: [$op] $scope | $title"
