#!/bin/bash
# 指定コミットの状態へ巻き戻す（write・前進のみ・非破壊）。
# 「黙って壊さない」不変条件のため reset --hard はしない:
#   1) 現状に未コミット変更があれば先に退避コミット（失っても戻せる）
#   2) 作業ツリー・index を対象ツリーへ完全一致させ（対象に無いファイルは削除）
#   3) それを「新しいコミット」として積む（履歴は線形・前進のみ。復元自体も巻き戻せる）
# usage: wiki-restore.sh <commit>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

target="${1:-}"
[ -n "$target" ] || { echo "usage: wiki-restore.sh <commit>" >&2; exit 2; }

wiki_exists || { echo "Wiki 未初期化" >&2; exit 2; }
git_enabled || { echo "git が無効です（復旧不可）" >&2; exit 2; }
root="$(wiki_root)"
[ -d "$root/.git" ] || { echo "git 履歴がありません" >&2; exit 2; }

acquire_write_lock

# 対象コミットの存在確認
full="$(wiki_git rev-parse --verify -q "${target}^{commit}" 2>/dev/null || true)"
[ -n "$full" ] || { echo "コミットが見つかりません: $target" >&2; exit 2; }
short="$(wiki_git rev-parse --short "$full")"
subj="$(wiki_git log -1 --pretty=format:'%s' "$full")"

# 1) 未コミット変更を退避（失っても戻せるように）
wiki_git add -A
if ! wiki_git diff --cached --quiet; then
  wiki_git commit -q -m "snapshot | global | restore 前の自動退避"
fi

# 2) 作業ツリー・index を対象ツリーへ完全一致（対象に無い追跡ファイルは削除される）
wiki_git read-tree -u --reset "$full"

# 3) 差分が無ければ既に一致、あれば新コミットとして記録
if wiki_git diff --cached --quiet; then
  echo "既に $short の状態と一致しています（変更なし）"
  exit 0
fi
wiki_git commit -q -m "restore | global | $short へ復元（$subj）"
echo "復元しました: $short （$subj）"
echo "→ 検証:"
bash "$LLM_WIKI_LIB_DIR/wiki-validate.sh" || true
