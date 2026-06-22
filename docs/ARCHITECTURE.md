# LLM Wiki Plugin アーキテクチャ

LLM Wiki Plugin が「どうやって知識を蓄積・参照・整理するか」を、自動で行われる部分・手動が必要な部分・整理機構の思想とともに記述する。**Claude Code ランタイムとの接合面（イベント・注入文・実行タイミング）の厳密仕様**は [`CLAUDE_CODE_INTEGRATION.md`](CLAUDE_CODE_INTEGRATION.md) に分離した。開発の規約・変更方針は [`../CLAUDE.md`](../CLAUDE.md) を、利用者向けの導入は [`../README.md`](../README.md) を参照。**人間が日々どう使うか（素材の置き場・取り込みの流れ・直接編集の運用）の利用ガイド**は [`USAGE.md`](USAGE.md)。

---

## 0. 設計思想 — なぜこの形か

中核は **「決定論スクリプト」と「LLM 判断」の分業**である。

- **間違えてはいけない定型操作** → `scripts/*.sh` に固定（構造生成・index/log 追記・リンク書換え・移動・slug 生成）。
- **判断を要する作業** → LLM に委譲（要約・統合・分類・スコープ選定・矛盾検出）。

狙いは、一般的な RAG が「問い合わせのたびに知識をゼロから再発見する」のに対し、**取り込み時に一度コンパイルして既存 Wiki に統合し、以後は最新に保つ**累積成果物を作ること。新機能を足すときもこの境界を守る — 定型操作はスクリプトへ、判断はスキルの手順へ。

---

## 1. 2つの世界（混同禁止）

| | プラグイン（このリポジトリ） | Wiki データ |
|---|---|---|
| 場所 | `llm-wiki-plugin/` | `~/.llm-wiki/`（`LLM_WIKI_HOME` で上書き可） |
| 中身 | scripts / skills / hooks | ナレッジページ・index・log |
| 変更手段 | 機能開発で直接編集 | スクリプト経由が原則（→ §7 で人間の直接編集も扱う） |

---

## 2. 5つの層

```
┌─ hooks/hooks.json ───────────── 暗黙参照（自動注入）
│    SessionStart     → wiki-context.sh session
│    UserPromptSubmit → wiki-context.sh prompt
├─ skills/ ────────────────────── /wiki-* コマンド＋自動トリガ（手順書）
│    llm-wiki（中核知識スキル）＝規約・手順・テンプレ
│    wiki-ingest / wiki-query / wiki-lint / wiki-move / wiki-topic / wiki-init
├─ agents/*.md ────────────────── read重い／並列フェーズの隔離実行（skills から委譲）
│    wiki-source-analyst（ingest 前半・raw 保存）/ wiki-auditor（lint 意味監査・並列）
│    wiki-researcher（query 大規模調査）  ※read・判断のみ／書き込みは本流
├─ scripts/*.sh ───────────────── 全操作の実体（決定論）
│    read 系: wiki-path / wiki-search / wiki-validate / wiki-context / wiki-slug
│    write 系: wiki-init / wiki-index-upsert / wiki-log / wiki-move（flock）
│    共通基盤: _lib.sh（root 解決・存在判定・ロック）
└─ ~/.llm-wiki/ ───────────────── データ（config.yml / log.md / global / topics）
```

サブエージェント層は **read が重い／独立並列にできる判断フェーズ**（巨大ソースの読解・全ページの意味監査・多ホップ調査）を本流コンテキストから隔離するために skills が委譲する。**書き込み（`wiki.lock` で直列化）とユーザ確認は本流に集約**し、エージェントは提案／findings／回答だけ返す（唯一の例外は `wiki-source-analyst` の `<scope>/raw/` 保存＝簿記でなく flock 対象外）。フックからは起動しない。委譲基準・返却契約は [`operations.md`](../skills/llm-wiki/references/operations.md) の「サブエージェント委譲」。

### `_lib.sh` が握る3つの不変条件

- `wiki_root()` — `LLM_WIKI_HOME` → `$HOME/.llm-wiki` の順で解決。
- `wiki_exists()` — 未初期化（root と config.yml が無い）なら、read 系・フックは **無出力で exit 0**。セッションを止めない。
- `acquire_write_lock()` — `$root/.lock/wiki.lock` への単一グローバル flock。write 系は書き込み前に必ず取得し、単一 Wiki を複数セッションが触っても直列化する。

---

## 3. データモデル — 整理機構の正体

知識は **3つの索引構造** で「グラフ」として保たれる。

| 機構 | 形式 | 役割 | 維持方法 |
|---|---|---|---|
| **ページ** | `<scope>/wiki/<種別>/<slug>.md` ＋ YAML frontmatter | 知識の実体。本文の `[[...]]` が発リンクの正本 | テンプレを `cp` → LLM が記入 |
| **index.md** | `- [[link]] — 要約 \| kw: 検索語` | スコープ内カタログ。`kw:` が日本語検索と自動参照照合の弱点を補う | `wiki-index-upsert.sh` |
| **log.md** | `## [日時] op \| scope \| title` | 全操作の時系列（`grep "^## \["` でパース可） | `wiki-log.sh`（flock） |

- **スコープ** = `global`（横断的・トピックに属さない）または `topics/<topic>`。両者は同一構造。
- **リンク** = 絶対形 `[[scope/wiki/page_type/slug]]`（ファイル実体パスに一致）が正本。短縮形 `[[slug]]` は同一ディレクトリ内のみ許可。
- **slug** = `wiki-slug.sh` が決定論生成（ASCII 小文字化／日本語そのまま保持／漢字のローマ字化はしない）。
- **既定種別** = papers / articles / concepts / entities。decisions / queries / journal はオプトイン（`/wiki-topic`）。
- **config.yml** = トピック・種別の意味を持つ正本だが **スクリプトは機械パースしない**。列挙はディレクトリ構造から得る。config と実体の乖離は `wiki-validate.sh` が検出。

---

## 4. 自動でやること vs 手動が要ること

運用の肝。**蓄積はほぼすべてユーザ起点** である点に注意。

| フェーズ | 自動（フック / スクリプト） | 人間の判断・起動が必要 |
|---|---|---|
| **参照** | SessionStart で所在注入／UserPromptSubmit で関連時にリマインド注入 | （なし＝意識せず参照される） |
| **取り込み** | slug 生成・index/log 追記・リンク整合 | ソース提示・要点確認・スコープ選定・取り込み起動（`/wiki-ingest`） |
| **整理** | validate の機械検査（リンク切れ・孤立・整合） | lint 起動・矛盾／陳腐化の判断・修正承認 |
| **再編** | move／topic 改名のリンク書換え・index 更新・log（`wiki-links` で被リンク確認） | move／改名の起動・移動先判断 |
| **手動作成** | slug 生成・テンプレ配置・frontmatter 記入・index/log（`wiki-new`） | 種別/スコープ判断・本文記入（`/wiki-new`） |
| **版管理** | Stop フックがターン単位で変更を git コミット（`wiki-commit`／§6） | 復元の判断・起動（`wiki-restore`） |

完全に自動なのは2つ — **暗黙参照**（処理前のコンテキスト注入）と **git 自動コミット**（ターン終了後の版管理）。どちらもフック起動で、ユーザは意識しない。

### 暗黙参照の挙動

`hooks.json` が `wiki-context.sh` を2モードで呼ぶ。出力契約は JSON `{"hookSpecificOutput":{"hookEventName":..,"additionalContext":..}}`。未初期化時は無出力 exit 0。

- **SessionStart** — Wiki の所在・トピック・ページ種別・「回答前に index.md を Read せよ」＋「再利用価値ある知見は取り込みを提案せよ（Proactive Capture）」を全セッションに注入。
- **UserPromptSubmit** — プロンプトを各 index の `kw:` 行＋トピック名と **部分文字列照合** し、ヒット時のみ「index を参照せよ」を軽量注入。無関係作業では無出力。`config.yml: auto_reference: false` で抑止。

---

## 5. 知識を蓄積するライフサイクル

```
ソース（URL / ファイル）
   │  /wiki-ingest <path-or-url> [topic]
   ▼
1. 取得（WebFetch / Read）→ 取得元メタを <scope>/raw/ に記録・source_id を控える
2. wiki-search.sh で重複検出（あれば「更新」に倒す）
3. 要点・種別・スコープ案を提示し【ユーザ確認】
      ├ 既存トピックに属す  → topics/<topic>
      ├ どこにも収まらない  → 新トピック作成を積極提案（/wiki-topic add）
      └ 横断的            → global
4. テンプレ cp → frontmatter＋本文記入（slug は wiki-slug.sh）
5. 波及更新は限定（直接言及 entity/concept ＋ index の kw 一致ページのみ）／相互リンク
6. wiki-index-upsert.sh で index、wiki-log.sh で log
7. wiki-validate.sh で検証
```

蓄積の入口はもう1つ、**ユーザ自身の知識を手で起こす** `/wiki-new` がある。ソース駆動の ingest と対になる、記述駆動の経路。`wiki-new.sh` がテンプレ雛形に frontmatter を埋めて所定の場所に置き、本文はユーザ（または記述からの LLM 下書き）が埋める。

加えて2つの補助経路がある。

- **Proactive Capture** — Web 調査での新知見・根本原因の解明・複数ソースの合成など再利用価値が出たとき、回答末尾で「Wiki に取り込みますか？」と一言提案（同一セッションで繰り返さない）。SessionStart 注入で常時意識される。
- **Query 還元** — `/wiki-query` の回答が比較・分析など再利用価値を持てば queries ページとして還元（確認付き）。

---

## 6. 並行・原子性・冪等性

- **直列化** — log/index/move の書き込みは `wiki.lock` への flock で直列化（write 系が内部で処理）。
- **冪等性** — `wiki-init.sh` は既存ファイルを上書きしない。初期化と移行は分けて考える（既存データの安全弁）。
- **未初期化耐性** — read 系・フックは未初期化なら無出力 exit 0。セッションを壊さない。

### Git 自動バージョン管理（安全網）

Wiki データは git で版管理される。**「あれば効く安全網」であって必須依存ではない** — `git` が無い／`config.yml: git: false` でも write は通常どおり成功する（read 系・フックがセッションを止めないのと同じ精神）。

- **コミットの単位** — Stop フック（`wiki-commit.sh`）がターン終了ごとに、そのターンの変更を **1 コミット**にまとめる。1 回の論理作業（ingest が内部で起こす new+index+log+リンク更新など）が 1 コミットに対応する。変更がなければ no-op。
- **ステージ範囲** — `git add -A` ではなく既知構造（`config.yml`/`log.md`/`.gitignore`/`global/`/`topics/`）に限定。ルート直下に紛れた想定外ファイル（秘密情報等）を巻き込まない。バイナリ原典（`raw/` の非テキスト）は `.gitignore` で除外し、抽出済みテキスト（`.md`）のみ追跡。
- **ローカル限定** — 固定アイデンティティ（`user.name=llm-wiki`）・署名なしでコミットし、**push はしない**。ユーザの git 設定にも依存しない。
- **非破壊な復元** — `wiki-restore.sh <hash>` は `reset --hard` をせず、未コミット変更を退避コミットしてから対象ツリーへ一致させ **新コミットとして積む**。履歴は前進のみで復元自体も巻き戻せる。`wiki-history.sh` で候補 hash を確認する。
- **遅延移行** — 既存 Wiki に repo が無ければ初回コミット時に `git init` する（冪等）。

接合面（フックのタイミング・タイムアウト・no-op 条件）の厳密仕様は [`CLAUDE_CODE_INTEGRATION.md` §4.2](CLAUDE_CODE_INTEGRATION.md)。

---

## 7. 人間も Wiki を編集する運用

設計の既定は「LLM が更新、人間はソース収集と問いを投げる」だが、人間が直接ページを書きたい／直したい場合がある。**層ごとに権限を分ける** ことで安全に共存できる。

| 層 | 人間の直接編集 | 理由 |
|---|---|---|
| **コンテンツ層**（ページ本文・frontmatter のメタ） | ◯ 自由に編集してよい | ただの Markdown。整合に影響しない |
| **簿記層**（index.md / log.md / リンク `[[..]]` / slug / ページの移動・改名） | ✗ スクリプト経由 | 手で触ると参照グラフが壊れる |

### 推奨ワークフロー

1. **既存ページの加筆・修正** — エディタで本文を直接編集してよい。`updated:` を直すと丁寧。要約が変わったら後述の reconcile で index に反映する。
2. **新規ページを手で追加** — 可能なら `/wiki-ingest` を使う。手で置く場合は最低限、`wiki/<種別>/` 配下に置き frontmatter 必須項目（title/page_type/scope/created/updated）を埋める。slug は `wiki-slug.sh "<title>"` で生成すると規則に揃う。
3. **編集後に整合を回復（reconcile）** — `/wiki-lint` を実行する。`wiki-validate.sh` が **index 未掲載・孤立・リンク切れ・frontmatter 欠落** を検出するので、LLM がスクリプト経由で修復する（index は `wiki-index-upsert.sh`、移動忘れは `wiki-move.sh`）。
4. **移動・改名は手で `mv` しない** — リンクが切れる。必ず `/wiki-move`。手で動かしてしまったら `/wiki-lint` で検出し、本来の `wiki-move` 相当をスクリプトで修復する。

つまり **「コンテンツは人間も自由、簿記は lint で回収」** が原則。validate がドリフトを検出する設計なので、人間の編集は「後から reconcile できる範囲」で許容される。

---

## 8. 既知の制約・スケール時の注意

- **index の分割は未自動化** — 150 行超で validate が警告するが分割スクリプトは無い。当面はトピック分割で対処する（オンディスク形式変更を伴う分割を入れる場合は CLAUDE.md の移行方針に従う）。
- **UserPromptSubmit は部分文字列照合** — 短い `kw:`（例 `rag`）は誤ヒットしうる。まだ index に無い新知識は照合対象外。`kw:` に短すぎる語を入れない運用で緩和。
- **スキーマ版管理は最小** — `config.yml: version` はあるが移行検出には未活用。形式変更時は CLAUDE.md の「移行の仕掛け」を必ず添える。

---

## 9. ファイル早見表

| パス | 役割 |
|---|---|
| `scripts/_lib.sh` | root 解決・存在判定・slug・flock の共通基盤 |
| `scripts/wiki-context.sh` | フック本体（session/prompt）。暗黙参照の注入 |
| `scripts/wiki-{init,index-upsert,log,new,move,rename-topic}.sh` | write 系（flock 保護）。`wiki-new`=手動ページ雛形、`wiki-rename-topic`=トピックをサブツリーごと改名 |
| `scripts/wiki-{path,search,validate,slug,links,traverse,graph}.sh` | read 系。`wiki-links`=1 ホップの発/被リンク・index 掲載、`wiki-traverse`=N ホップ近傍収集、`wiki-graph`=全グラフ俯瞰（島・孤立・ハブ） |
| `skills/llm-wiki/` | 中核知識スキル。規約 `references/conventions.md`・手順 `references/operations.md`・雛形 `assets/templates/` |
| `skills/wiki-*/SKILL.md` | 各 `/wiki-*` コマンドの手順書 |
| `hooks/hooks.json` | SessionStart / UserPromptSubmit の登録 |
