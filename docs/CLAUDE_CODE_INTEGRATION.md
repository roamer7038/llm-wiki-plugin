# Claude Code 連携リファレンス

このプラグインが **Claude Code のエージェント処理の前後に、具体的に何を注入し・何を起こすか** を明文化する。

[`ARCHITECTURE.md`](ARCHITECTURE.md) が「知識をどう蓄積・整理するか（Wiki 側の思想）」を扱うのに対し、本書は **プラグインと Claude Code ランタイムの接合面**（イベント・注入文・実行タイミング）だけを扱う。実装の根拠は `hooks/hooks.json` と `scripts/wiki-context.sh`。

---

## 1. 連携は3面だけ。自動はそのうち1面

| 面 | 実体 | 起動 | エージェント処理との関係 |
|---|---|---|---|
| **Hooks** | `hooks/hooks.json` → `wiki-context.sh` | Claude Code が**自動**で実行 | **処理の前**にコンテキストを注入する（唯一の完全自動） |
| **Skills** | `skills/*/SKILL.md` | モデルが説明文で**自動判断** or ユーザが `/wiki-*` | エージェント処理**の中**で手順書として読み込まれる |
| **Scripts** | `scripts/*.sh` | モデルが Bash ツールで呼ぶ | エージェント処理**の中**でツール実行として走る |

要点: **エージェントの「前」に自動で起きるのは Hooks だけ。** Skills と Scripts は「エージェントが自分で起動する」ものであって、自動注入ではない。`PreToolUse` / `PostToolUse` / `Stop` フックは**持たない**（§5 参照）。

---

## 2. プラグインの登録と解決

- `.claude-plugin/plugin.json` がマニフェスト。Claude Code は規約ディレクトリ（`hooks/` `skills/` `scripts/`）を**自動検出**する。専用の `commands/` ディレクトリは持たず、`/wiki-*` コマンドは skills がそのまま担う。
- パス参照は `${CLAUDE_PLUGIN_ROOT}`（プラグイン実体の絶対パス）で解決。hooks も skills 内の手順も、スクリプトを `bash ${CLAUDE_PLUGIN_ROOT}/scripts/...` で呼ぶ。
- Wiki データの場所はプラグインと**別**。`LLM_WIKI_HOME` → `$HOME/.llm-wiki` の順で `_lib.sh: wiki_root()` が解決する。

---

## 3. タイムライン — いつ何が注入されるか

### セッション開始時（1回）

```
Claude Code 起動
  └─ SessionStart フック発火
       └─ bash wiki-context.sh session   （timeout 10s）
            ├─ Wiki 未初期化      → 無出力 exit 0（何も注入されない）
            └─ 初期化済み         → additionalContext を JSON で stdout
                 → モデルのコンテキスト先頭付近に注入される
```

注入される文（`session` モード、`$root`・`$topics`・`$ptypes` は実行時に埋まる）:

```
[LLM Wiki] <root> にナレッジベースがあります。
トピック: <topics>
ページ種別: <page_types>
知識・事実・調査を要する質問に答える前に、該当スコープの index.md（例: <root>/global/index.md）を Read し、関連ページを辿ってから出典付きで回答すること。
このセッションで、Web 調査による新たな知見・複雑な問題の根本原因と解決策・複数ソースを合成した再利用価値ある結論が得られたら、回答末尾で wiki-ingest による取り込みを一言提案すること（既存知識・一時的なデバッグ・単純な編集では提案しない。同一セッションで繰り返さない）。
取り込み・整理・lint・移動などの操作は llm-wiki スキルの手順に従う。
```

この1注入が「暗黙参照」と「Proactive Capture の判定基準」の両方を担う。**Stop フックを使わず、判定基準を常駐文に畳み込む**のが現行設計（§5）。

### ユーザの1ターンごと

```
ユーザがプロンプト送信
  └─ UserPromptSubmit フック発火（モデルがプロンプトを見る前）
       └─ bash wiki-context.sh prompt   （timeout 10s、stdin に prompt JSON）
            ├─ config.yml: auto_reference: false  → exit 0（抑止）
            ├─ プロンプトが kw/トピック名に無関係 → exit 0（無注入）
            └─ 部分文字列ヒット → additionalContext を注入
  └─ モデルがプロンプト＋（あれば）注入文を処理
       ├─ 説明文一致 or /wiki-* で Skill が起動 → 手順書を読み込む
       ├─ 手順に従い Scripts を Bash ツールで実行（read/write）
       └─ 応答。基準を満たせば末尾に取り込み提案（Proactive Capture）
  └─ ターン終了（Stop フックは無い＝自動で何も起きない）
```

`prompt` モードの照合アルゴリズム（`wiki-context.sh`）:

1. `global/index.md` と全 `topics/*/index.md` の **`kw:` 行のみ**を抽出し、`,`・`、` で分割してキーワード集合を作る（軽量・index 依存）。
2. それにトピック名を加える。
3. プロンプト文字列に対し各キーワードを**部分文字列照合**（`case "$prompt" in *"$k"*`）。1つでもヒットしたら注入。

注入される文（`prompt` モード）:

```
[LLM Wiki] この質問は既存ナレッジに関連する可能性があります。回答前に <root>/global/index.md と該当トピックの index.md を Read し、関連ページを参照して出典付きで答えること。
```

---

## 4. Hooks の契約（厳密仕様）

- **登録**: `hooks/hooks.json` の `SessionStart` と `UserPromptSubmit`、いずれも `matcher: "*"`、`timeout: 10`（秒）。
- **出力契約**: stdout に1行 JSON。`jq` で生成する。
  ```json
  {"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"…"}}
  ```
  `additionalContext` の文字列がそのままモデルのコンテキストに足される。
- **未初期化耐性**: `wiki_exists()` が偽（root も config.yml も無い）なら**無出力で exit 0**。セッションやプロンプト処理を一切妨げない。
- **抑止**: `prompt` モードのみ `config.yml: auto_reference: false`（既定 `true`）で完全無効化できる。`session` モードに抑止スイッチは無い。
- **副作用**: read-only。Wiki を書き換えない。flock も取らない。
- **失敗時**: `set -euo pipefail`。10s 超過や異常終了は Claude Code 側でハンドリングされ、注入が無いだけでセッションは継続する。

---

## 5. 注入されないもの・自動で起きないこと（重要）

接合面を誤解しないために、**やっていないこと**を明示する。

- **`PreToolUse` / `PostToolUse` フックは無い。** スクリプト実行前後にプラグインが割り込むことはない。スクリプトは「モデルが Bash ツールで呼ぶ普通のコマンド」にすぎない。
- **`Stop` / `SubagentStop` フックは無い。** ターン終了時に自動で発火する処理は存在しない。Proactive Capture の提案は Stop フックではなく、SessionStart 注入文の判定基準（§3）に基づくモデルの判断で行う。Stop フックは毎ターン発火してノイズになるため追加しない。
- **Proactive Capture は「フック」ではなく「注入された指示」。** 取り込み提案が出るかはモデルの判断で、ランタイムの自動処理ではない。
- **Skill の自動起動はプラグインではなく Claude Code が決める。** トリガは各 `SKILL.md` の `description`。プラグインは説明文を書くだけで、発火可否はモデル側の照合に委ねる。

---

## 6. Skills と Scripts の接合

### Skills

- `skills/<name>/SKILL.md` の frontmatter `description` が**自動起動のトリガ**であり、同時に `/<name>` スラッシュコマンドの実体でもある（`commands/` は不要）。
- 中核は `llm-wiki` スキル。規約 `references/conventions.md`・手順 `references/operations.md`・雛形 `assets/templates/` を抱え、`wiki-ingest` / `wiki-query` / `wiki-lint` / `wiki-move` / `wiki-topic` / `wiki-init` はそれを参照する薄い手順書。
- スキルは**判断**（要約・分類・スコープ選定・矛盾検出）を担い、**定型操作はスクリプトに委譲**する。これが設計の核（[`ARCHITECTURE.md` §0](ARCHITECTURE.md)）。

### Scripts

- スキルの手順に従い、モデルが `bash ${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh ...` を **Bash ツール呼び出し**として実行する。1スクリプト＝1ツール実行。
- すべて `_lib.sh` を source。
  - **read 系**（`wiki-path/search/validate/context/slug/links`）— ロック不要。未初期化なら無出力 exit 0。
  - **write 系**（`wiki-init/index-upsert/log/new/move/rename-topic`）— 書き込み前に `acquire_write_lock()` で `$root/.lock/wiki.lock` への単一 flock を取得し、複数セッションの同時書き込みを直列化。
- 外部依存は `bash` / `python3` / `jq` / `flock` のみ。複雑なテキスト操作は bash 内ヒアドキュメント Python（値は環境変数で受け渡し）。

---

## 7. イベント早見表

| Claude Code イベント | プラグインの反応 | 自動/モデル駆動 | 副作用 |
|---|---|---|---|
| プラグインロード | hooks/skills/scripts を自動検出 | 自動 | なし |
| **SessionStart** | `wiki-context.sh session` → 所在＋参照＋Proactive Capture 基準を注入 | 自動 | read-only |
| **UserPromptSubmit** | `wiki-context.sh prompt` → kw 照合ヒット時のみ参照リマインド注入 | 自動 | read-only |
| プロンプト処理中 | 説明文一致／`/wiki-*` で Skill 起動 | モデル駆動 | なし |
| Skill 手順実行 | Scripts を Bash で実行（read は随時／write は flock） | モデル駆動 | write 系のみ Wiki を更新 |
| 応答末尾 | 基準を満たせば取り込み提案（注入指示に基づく判断） | モデル駆動 | なし |
| **ターン終了 (Stop)** | **何もしない**（Stop フック未登録） | — | なし |

---

参照: 接合面の根拠は `hooks/hooks.json` と `scripts/wiki-context.sh`。Wiki 側のデータモデル・蓄積ライフサイクルは [`ARCHITECTURE.md`](ARCHITECTURE.md)、開発規約は [`../CLAUDE.md`](../CLAUDE.md)。
