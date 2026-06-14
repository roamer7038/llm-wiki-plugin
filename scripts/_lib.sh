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

# ---- Git バージョン管理（任意・安全網） ----
# 思想: git は「あれば効く安全網」であって必須依存ではない。git が無い／無効でも
# write 操作は成功させる（read 系・フックがセッションを止めないのと同じ精神）。
# 自動コミットは Stop フック（wiki-commit.sh）がターン単位でまとめて行う。

# git コマンドがあり config.yml に `git: false` が無ければ有効（既定は有効）。
git_enabled() {
  command -v git >/dev/null 2>&1 || return 1
  ! grep -qE '^git:[[:space:]]*false' "$(wiki_root)/config.yml" 2>/dev/null
}

# 固定アイデンティティ・署名なしで git を実行（ユーザの git 設定に依存しない）。
wiki_git() {
  git -C "$(wiki_root)" \
    -c user.name=llm-wiki -c user.email=llm-wiki@localhost \
    -c commit.gpgsign=false "$@"
}

# リポジトリ未作成なら init し .gitignore を用意（冪等）。git 無効なら何もしない。
# 既存 Wiki への遅延移行を兼ねる（初回 commit 時に repo を立てる）。
wiki_git_init() {
  git_enabled || return 0
  local r; r="$(wiki_root)"
  [ -d "$r/.git" ] && return 0
  wiki_git init -q
  [ -f "$r/.gitignore" ] || cat > "$r/.gitignore" <<'EOF'
# 排他ロック（実行時のみ）
.lock/
# バイナリ・非テキスト原典は履歴に含めない（版管理するのは知識テキストのみ）。
# raw/ の生バイト原典は対象外。抽出済みテキスト(.md)は通常どおり追跡される。
*.png
*.jpg
*.jpeg
*.gif
*.webp
*.bmp
*.ico
*.tif
*.tiff
*.svgz
*.pdf
*.doc
*.docx
*.xls
*.xlsx
*.ppt
*.pptx
*.odt
*.ods
*.odp
*.zip
*.tar
*.gz
*.tgz
*.bz2
*.xz
*.7z
*.rar
*.mp3
*.mp4
*.m4a
*.mov
*.avi
*.wav
*.flac
*.webm
*.mkv
*.exe
*.dll
*.so
*.dylib
*.bin
*.o
*.a
*.woff
*.woff2
*.ttf
*.otf
*.eot
EOF
}

# 変更があれば 1 コミットを作る（メッセージ指定）。無変更なら no-op。git 無効なら何もしない。
# 呼び出し側で acquire_write_lock を保持していること。
wiki_git_commit() {
  git_enabled || return 0
  wiki_git_init
  wiki_git add -A
  if wiki_git diff --cached --quiet; then return 0; fi
  wiki_git commit -q -m "$1"
}
