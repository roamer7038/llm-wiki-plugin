# LLM Wiki 操作手順（詳細）

すべてのスクリプトは `${CLAUDE_PLUGIN_ROOT}/scripts/` にある。`<scope>` は `global` または `topics/<topic>`。

## Ingest（取り込み）

目的: 1 ソースを取り込み、要約ページ＋関連ページ更新＋index/log を維持する。

1. **取得と保存**
   - URL は WebFetch、ローカルは Read で取得。
   - **取得元を一意特定できるメタ情報**（URL・取得日・`source_id`、ローカルならパスと hash）を `<scope>/raw/sources.md` に追記する。
   - **原則として、LLM が実際に読んだ抽出テキストを `<scope>/raw/<source_id 由来のファイル名>.md` にスナップショット保存する。** これは要約の事後検証・モデル更新時の再蒸留・リンク腐敗対策のための「原典の地に足のついた真実」であり、`raw/` は不変（読むだけ）に扱う。保存するのは生バイト（HTML/PDF）ではなく、WebFetch / Read で得た**抽出済みテキスト**でよい（軽量かつ要約の根拠そのもの）。
   - 次の場合に**限り**全文保存を省略しメタのみとしてよい: 著作権上まずい（有料記事・書籍）／巨大・バイナリで抽出が非現実的／公的な恒久 URL（RFC・仕様書）でリンク腐敗リスクが低い。省略時は `raw/sources.md` にその理由を一行記す。
   - `source_id` を決める: URL は正規化（クエリ除去等）、ファイルは `sha1sum` 等の hash。
2. **重複検出**
   - `wiki-search.sh "<title>"` および `wiki-search.sh "<source_id>"` で既存を確認。
   - 既存ページがあれば**新規作成せず更新**する。
3. **読解と提案**
   - 要点、該当 `page_type`、スコープ（global か特定 topic か）を整理し、ユーザに提示して**確認を取る**。
   - スコープ判別が曖昧なら global に置く。
4. **ページ作成/更新**
   - slug を `wiki-slug.sh "<title>"` で生成。
   - テンプレを配置: `cp ${CLAUDE_PLUGIN_ROOT}/skills/llm-wiki/assets/templates/<page_type>.md <scope>/wiki/<page_type>/<slug>.md`
   - frontmatter（title/aliases/scope/created/updated/source_* 等）と本文を埋める。
5. **波及更新（範囲を限定）**
   - 更新対象は「原典が直接言及する entity/concept」＋「該当スコープ index の `kw:` に一致する既存ページ」のみ。
   - 各ページに相互リンク `[[...]]`（絶対形）を張る。
   - 新事実が既存ページと矛盾する場合は該当ページに注記し、必要なら `decisions` か `overview` を更新。
6. **index と log**
   - 触れた各ページについて `wiki-index-upsert.sh <scope> <page_type> <slug> "<要約>" "<kw...>"`。
   - `wiki-log.sh ingest <scope> "<title>" "<bullet1>" "<bullet2>" …`。
7. **検証**: `wiki-validate.sh <scope>` でリンク切れ等を確認。

## Query（問い合わせ）

1. 質問に関連するスコープを判断し、`<scope>/index.md` を Read。
2. 関連ページを辿って Read。必要に応じ `wiki-search.sh "<query>" [scope]`。
3. **出典付き**で回答（参照したページを示す）。
4. 回答が比較・分析など再利用価値を持つなら、queries ページとして**還元するか確認**。
   - 還元時: `queries` テンプレで作成 → `wiki-index-upsert.sh` → `wiki-log.sh query <scope> "<問い>" …`。

## Lint（健全性チェック）

1. `wiki-validate.sh [scope]` を実行（リンク切れ／孤立／index⇔ファイル／config⇔ディレクトリ／必須 frontmatter／superseded_by／index 肥大化／log 形式）。
2. 機械検査に LLM の観点を加える:
   - **矛盾**: 相反する主張のあるページ対。
   - **陳腐化**: 新ソースに更新された古い記述。
   - **孤立**: inbound 0 のページに適切なリンクを追加すべきか。
   - **不足概念**: index に頻出するが専用ページが無い概念。
   - **未 entity 化**: 複数ページに頻出する固有名詞（人物・組織・プロダクト・手法）で `entities` ページが無いもの。entity を作って各ページからリンクすると、スコープ内に閉じがちなリンクをグラフとして繋げられる（特に papers/concepts に偏り entities が空のときに有効）。
   - **データギャップ**: Web 検索で埋められる欠落。具体的な検索クエリを提案。
   - **原典スナップショット未保存**: papers/articles で `source_id` を持つのに `raw/` に抽出テキストのスナップショットが無いページ（旧方針のメタのみ取り込み）。`sources.md` に省略理由が記録されていなければ、原典 URL を再取得してスナップショットを保存し直すことを提案する（リンク腐敗で再取得不能になる前に）。恒久 URL・著作権等の正当な省略は対象外。
   - **次の問い**: 深掘りすべき調査テーマを提案。
3. 修正の適用は**ユーザ確認後**。適用したら index/log をスクリプトで更新。

### 人間の手編集後の reconcile

人間が直接ページを加筆・新規作成・削除・改名した後は lint がドリフトを検出する。スクリプト経由で回復する:

- **index 未掲載 / 要約が古い** → `wiki-index-upsert.sh <scope> <page_type> <slug> "<要約>" "<kw>"` で追加・更新。
- **リンク切れ（手で mv/rename した）** → 本来の移動を `wiki-move.sh <from-ref> <to-ref>` で行い直す（既に手で動かして実体が移動済みなら、index/リンクの不整合を個別に upsert・修正してから validate を通す）。
- **frontmatter 欠落** → 必須項目（title/page_type/scope/created/updated）を補う。
- 回復後は再度 `wiki-validate.sh` を通し、ERROR が消えたことを確認する。

## New（手動ページ作成）

目的: ユーザ自身の知識を、テンプレ済みのページとして起こす（ソース駆動の Ingest とは別物）。

1. page_type とスコープを判断し、ユーザに確認。
2. `wiki-search.sh "<title/別名>"` で重複確認（あれば更新に倒す）。
3. `wiki-new.sh <scope> <page_type> "<title>" ["<要約>"] ["<kw>"]` で雛形作成（slug 生成・テンプレ配置・frontmatter 記入・index upsert・log を一括、作成パスを返す）。既存があれば上書きせずエラー。
4. ユーザの記述があれば本文を下書き（placeholder `<...>` を実内容に置換）。無ければ placeholder のまま渡してよい。
5. `wiki-links.sh`/`wiki-search.sh` で近傍を探し相互リンク。**未使用の placeholder リンク `[[<...>]]` は削除**する。
6. `wiki-validate.sh <scope>` で検証。

## Links / グラフ確認

- `wiki-links.sh <ref> [--inbound|--outbound]` — 1 ホップの発リンク・被リンク・index 掲載状況。再編前の影響確認（誰がこのページを指すか）・孤立調査に。
- `wiki-traverse.sh <ref> [--depth N] [--outbound|--inbound|--both]` — 起点から N ホップ辿って近傍ページを index 要約つきで収集（既定 depth=2, both）。回答前の文脈集めに（検索で起点→辿る）。
- `wiki-graph.sh [--summary|--json|--dot] [scope]` — グラフ全体の俯瞰。連結成分（島）・孤立ページ・被リンクハブ・リンク切れを一覧。
- ref は `scope/wiki/page_type/slug` 形式。

## Move / Rename / 再編

- 再編前に `wiki-links.sh <ref>` で被リンクを確認し、影響範囲を把握してから実行する。
- **ページ**の rename（同スコープ・slug 変更）・別スコープへの move・トピック切り出しは `wiki-move.sh <from-ref> <to-ref>`。
  - 例: `wiki-move.sh global/wiki/concepts/機械学習 topics/ml/wiki/concepts/機械学習`
  - ファイル移動・frontmatter 更新・全 inbound リンク書換え・両スコープ index 更新・log 追記を一括で行う。
- **トピック**の改名は `wiki-rename-topic.sh <old> <new>`（トピック名のみ。`topics/` や `/` は付けない）。
  - 例: `wiki-rename-topic.sh ml machine-learning`
  - サブツリーごと改名し、配下全ページの scope・全 wiki の `[[topics/<old>/...]]` リンク・config.yml の topics 名・各 index を更新する。互換維持・再整理の道具。
- 手で `mv` したり index を手書きしない（リンク切れの原因になる）。

## トピック / 種別の追加・削除

- `/wiki-topic add <name> [desc]` / `/wiki-topic remove <name>` / `/wiki-topic list`。
- config.yml の更新と対応ディレクトリの作成/退避を同期し、log に記録する。
- ページ種別の追加も同様（`global/wiki/<name>/` と各 topic に作成）。

## 履歴 / 復旧（Git バージョン管理）

Wiki は git で自動バージョン管理される（`config.yml: git: true` のとき。`git` コマンドが無ければ自動的に無効・write は通常どおり成功）。コミットは **Stop フック（`wiki-commit.sh`）がターン単位で自動実行**する — 1 回の論理作業（ingest が内部で起こす new+index+log+リンク更新など）が 1 コミットにまとまる。手動でコミットを打つ必要はない。

- `wiki-history.sh [scope] [count]` — 変更履歴を `<hash>  <日時>  op | scope | title` で表示（既定 20 件）。「最近どう変わったか」「どこまで戻せるか」の確認に。
- `wiki-restore.sh <hash>` — 指定コミットの状態へ**非破壊で巻き戻す**。`reset --hard` はしない: 未コミット変更を退避コミットしてから対象ツリーへ一致させ、**新しいコミットとして積む**。履歴は前進のみで、復元自体もさらに巻き戻せる。実行後に `wiki-validate.sh` を自動実行する。
- ユーザが「さっきの取り込みを取り消したい / 前の状態に戻したい」と言ったら、`wiki-history.sh` で候補 hash を提示 → 合意の上で `wiki-restore.sh <hash>`。
- バイナリ・非テキスト原典（PDF・画像・Office・アーカイブ等）は `.gitignore` で版管理対象外。版管理するのは知識テキスト（`.md`）のみ。

## チェックリスト（ingest 完了時）

- [ ] 抽出テキストを raw/ にスナップショット保存し（省略時は raw/sources.md に理由を記録）、source_id を控えた
- [ ] 重複を確認した（新規 or 更新の判断）
- [ ] slug をスクリプトで生成した
- [ ] frontmatter 必須項目を埋めた
- [ ] 相互リンクを絶対形で張った
- [ ] index を upsert した
- [ ] log に追記した
- [ ] validate を通した
