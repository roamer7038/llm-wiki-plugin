#!/bin/bash
# Stop フック: wiki が存在する場合のみ、知見の取り込み提案を促す
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

wiki_exists || exit 0

printf '{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"[LLM Wiki] 今回の作業でWeb調査・問題解決・合成など再利用価値のある知見があれば、wiki-ingest での取り込みをユーザーに提案してください。特になければ何もしなくて構いません。"}}\n'
