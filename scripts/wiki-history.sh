#!/bin/bash
# Wiki の変更履歴を表示（read-only）。git 有効・リポジトリありのときのみ。
# usage: wiki-history.sh [scope] [count]
#   scope: global | topics/<topic>（その配下に絞る）。数値だけなら count とみなす。
#   count: 表示件数（既定 20）。
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

wiki_exists || { echo "Wiki 未初期化"; exit 0; }
git_enabled || { echo "git 無効（履歴なし）"; exit 0; }
root="$(wiki_root)"
[ -d "$root/.git" ] || { echo "git 履歴なし（まだコミットされていません）"; exit 0; }

scope="${1:-}"; count="${2:-20}"
# 第1引数が数値だけなら count とみなす
if printf '%s' "$scope" | grep -qE '^[0-9]+$'; then count="$scope"; scope=""; fi

args=(log --no-color --date=format:'%F %H:%M' --pretty=format:'%h  %ad  %s' -n "$count")
[ -n "$scope" ] && args+=(-- "$scope")
wiki_git "${args[@]}"
echo
echo "（巻き戻し: wiki-restore.sh <hash>）"
