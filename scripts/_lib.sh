#!/bin/bash
# llm-wiki 共有ヘルパー。各スクリプトから source して使う。
# read 系・write 系で共通のルート解決／存在判定／slug／ロックを提供する。

set -euo pipefail

LLM_WIKI_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# プラグインルート（CLAUDE_PLUGIN_ROOT 優先、無ければ scripts の親）
LLM_WIKI_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$LLM_WIKI_LIB_DIR/.." && pwd)}"

# Wiki ルート: LLM_WIKI_HOME があれば優先、無ければ $HOME/.llm-wiki
wiki_root() { printf '%s' "${LLM_WIKI_HOME:-$HOME/.llm-wiki}"; }

# 初期化済みか（ルートと config.yml が存在）
wiki_exists() { local r; r="$(wiki_root)"; [ -d "$r" ] && [ -f "$r/config.yml" ]; }

# テンプレート配置ディレクトリ
wiki_templates_dir() { printf '%s' "$LLM_WIKI_PLUGIN_ROOT/skills/llm-wiki/assets/templates"; }

# title -> 決定論的 slug
slugify() { bash "$LLM_WIKI_LIB_DIR/wiki-slug.sh" "$@"; }

# 全書き込みを直列化する単一グローバルロックの fd を開く。
# 呼び出し側で acquire_write_lock した後に書き込み、スクリプト終了で自動解放。
acquire_write_lock() {
  local r; r="$(wiki_root)"
  mkdir -p "$r/.lock"
  exec 9>"$r/.lock/wiki.lock"
  flock 9
}
