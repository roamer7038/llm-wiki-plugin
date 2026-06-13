#!/bin/bash
# title から決定論的に slug を生成する。
# 規則: ASCII英字は小文字化／英数字・日本語(かな漢字等)・ハイフンを保持／
#       それ以外と空白は '-' に／'-' 連続は1個に畳み前後トリム／空なら短ハッシュ。
# 漢字→読みの変換(ローマ字化)は辞書依存で非決定的なため行わない。
set -euo pipefail

title="$*"
python3 - "$title" <<'PY'
import sys, re, hashlib, unicodedata
t = sys.argv[1]
low = t.lower()
out = []
for ch in low:
    if ('a' <= ch <= 'z') or ('0' <= ch <= '9') or ch == '-':
        out.append(ch)
    elif ord(ch) > 127 and (unicodedata.category(ch).startswith('L') or unicodedata.category(ch).startswith('N')):
        # 非ASCIIの文字・数字(日本語含む)は保持
        out.append(ch)
    else:
        out.append('-')
s = re.sub(r'-+', '-', ''.join(out)).strip('-')
if not s:
    s = 'p-' + hashlib.sha1(t.encode('utf-8')).hexdigest()[:8]
print(s)
PY
