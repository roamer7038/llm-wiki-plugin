# LLM Wiki 操作手順（詳細）

すべてのスクリプトは `${CLAUDE_PLUGIN_ROOT}/scripts/` にある。`<scope>` は `global` または `topics/<topic>`。

## Ingest（取り込み）

目的: 1 ソースを取り込み、要約ページ＋関連ページ更新＋index/log を維持する。

1. **取得と保存**
   - URL は WebFetch、ローカルは Read で取得。
   - **取得元を一意特定できるメタ情報**（URL・取得日・`source_id`、ローカルならパスと hash）を `<scope>/raw/`（例 `raw/sources.md`）に記録する。原典そのものの全文保存は任意（著作権・サイズの都合で省略してよい）。保存する場合は不変（読むだけ）に扱う。
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
   - **次の問い**: 深掘りすべき調査テーマを提案。
3. 修正の適用は**ユーザ確認後**。適用したら index/log をスクリプトで更新。

### 人間の手編集後の reconcile

人間が直接ページを加筆・新規作成・削除・改名した後は lint がドリフトを検出する。スクリプト経由で回復する:

- **index 未掲載 / 要約が古い** → `wiki-index-upsert.sh <scope> <page_type> <slug> "<要約>" "<kw>"` で追加・更新。
- **リンク切れ（手で mv/rename した）** → 本来の移動を `wiki-move.sh <from-ref> <to-ref>` で行い直す（既に手で動かして実体が移動済みなら、index/リンクの不整合を個別に upsert・修正してから validate を通す）。
- **frontmatter 欠落** → 必須項目（title/page_type/scope/created/updated）を補う。
- 回復後は再度 `wiki-validate.sh` を通し、ERROR が消えたことを確認する。

## Move / Rename / 再編

- rename（同スコープ・slug 変更）、別スコープへの move、トピック切り出しはすべて `wiki-move.sh <from-ref> <to-ref>`。
  - 例: `wiki-move.sh global/concepts/機械学習 topics/ml/concepts/機械学習`
  - ファイル移動・frontmatter 更新・全 inbound リンク書換え・両スコープ index 更新・log 追記を一括で行う。
- 手で `mv` したり index を手書きしない（リンク切れの原因になる）。

## トピック / 種別の追加・削除

- `/wiki-topic add <name> [desc]` / `/wiki-topic remove <name>` / `/wiki-topic list`。
- config.yml の更新と対応ディレクトリの作成/退避を同期し、log に記録する。
- ページ種別の追加も同様（`global/wiki/<name>/` と各 topic に作成）。

## チェックリスト（ingest 完了時）

- [ ] 原典を raw/ に保存し source_id を記録した
- [ ] 重複を確認した（新規 or 更新の判断）
- [ ] slug をスクリプトで生成した
- [ ] frontmatter 必須項目を埋めた
- [ ] 相互リンクを絶対形で張った
- [ ] index を upsert した
- [ ] log に追記した
- [ ] validate を通した
