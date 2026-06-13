# LLM Wiki 規約（全文）

## frontmatter

すべての wiki ページは YAML frontmatter を持つ。

| キー | 必須 | 内容 |
|------|------|------|
| `title` | ✓ | 日本語原文のタイトル |
| `aliases` | | 別名・表記揺れ・英語名。重複同定と検索補助に使う |
| `page_type` | ✓ | papers / articles / concepts / entities / decisions / queries / journal … |
| `scope` | ✓ | `global` または `topics/<topic>` |
| `created` | ✓ | 作成日 YYYY-MM-DD |
| `updated` | ✓ | 更新日 YYYY-MM-DD |
| `tags` | | 任意のタグ配列 |

種別ごとの追加メタ:

- **papers / articles**: `sources`（原典の逆引き配列）, `source_id`（重複検出用）, `source_type`（paper/article/book/web/note）
- **entities**: `entity_kind`（person/org/product/place）
- **decisions**: `date`, `status`（active/superseded）, `superseded_by`（status=superseded 時、`scope/page_type/slug`）
- **queries**: `question`, `sources`

発リンクの正本は本文の `[[...]]`。frontmatter に発リンク一覧は持たない。

## ファイル名 slug

- `wiki-slug.sh "<title>"` で生成（手で命名しない）。
- 規則: ASCII 英字は小文字化／英数字・日本語(かな漢字)・ハイフンを保持／その他と空白は `-`／`-` 連続は1個に畳み前後トリム。
- 漢字→読みのローマ字化は辞書依存で非決定的なため**行わない**。日本語はそのまま保持（例: 「機械学習」→ `機械学習.md`）。
- 同一スコープ・同一種別で slug が衝突し、かつ title/aliases 同定で**別ページ**と判断した場合のみ `-2`, `-3`… を付す（同一なら更新）。

## リンク

- 正本はスコープ修飾の絶対形: `[[scope/page_type/slug]]`。例 `[[global/concepts/機械学習]]`、`[[topics/rust/concepts/ownership]]`。
- 同一ディレクトリ内に限り短縮形 `[[slug]]` を許可。それ以外の短縮形は `wiki-validate.sh` が曖昧参照として警告。
- move/rename はリンク書換えを伴うため必ず `wiki-move.sh` 経由。

## index.md 形式

```
# Index — <scope>

## <page_type>
- [[<scope>/<page_type>/<slug>]] — <一行要約> | kw: <検索語, …>
```

- 種別見出しごとに 1 行 1 エントリ。
- `kw:` に日本語表記揺れ・英語キーワードを含め、grep 検索と自動参照の照合を補う。
- 追加・更新は `wiki-index-upsert.sh` で行う（手書きしない）。
- ページ数が増え index が肥大化したら（既定 150 行超で validate が警告）、`index/<page_type>.md` への分割を検討。

## log.md 形式

```
## [YYYY-MM-DD HH:MM] <op> | <scope> | <title>
- <bullet>
```

- `<op>`: init / ingest / query / lint / topic / move。
- `grep "^## \[" log.md` でエントリ一覧を取得可能。
- 追記は `wiki-log.sh` で行う（flock 保護）。

## config.yml

- トピック・種別の意味と説明を持つ正本（人間/LLM 用）。
- **スクリプトは config を機械パースしない**。page_types/topics の列挙はディレクトリ構造（`global/wiki/*/`・`topics/*/`）から得る。
- `auto_reference: false` で UserPromptSubmit による自動参照リマインドを無効化できる。
- config と実ディレクトリの乖離は `wiki-validate.sh` が検出する。

## 並行・原子性

- 単一グローバル Wiki を複数セッションが触りうるため、log/index/move の書き込みは `wiki.lock` による flock で直列化される（write 系スクリプトが内部で処理）。
