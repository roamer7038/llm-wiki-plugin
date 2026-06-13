#!/bin/bash
# naive 検索（read-only）。<query> [scope]
# index.md の kw:・本文・frontmatter(title/aliases) を横断 grep。重複同定にも使う。
# マッチ無しでも正常終了（set -e 下で grep の exit 1 を吸収）。
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

query="${1:-}"
scope="${2:-}"
[ -n "$query" ] || { echo "usage: wiki-search.sh <query> [scope]" >&2; exit 2; }
wiki_exists || { echo "Wiki 未初期化"; exit 0; }

root="$(wiki_root)"
if [ -n "$scope" ]; then
  targets=("$root/$scope")
else
  targets=("$root/global" "$root/topics")
fi

echo "# 検索: \"$query\"${scope:+ (scope=$scope)}"
echo

# 1) index.md の該当行（要約・kw）
echo "## index ヒット"
grep -rinF --include='index.md' -- "$query" "${targets[@]}" 2>/dev/null | sed 's/^/  /' || true
echo

# 2) ページ本文・frontmatter（title/aliases 含む）
echo "## ページ ヒット（ファイル: 行）"
grep -rilF --include='*.md' --exclude='index.md' -- "$query" "${targets[@]}" 2>/dev/null \
  | while IFS= read -r f; do
      line="$(grep -niF -m1 -- "$query" "$f" 2>/dev/null || true)"
      printf '  %s\n    %s\n' "${f#$root/}" "$line"
    done || true
