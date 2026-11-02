# 既存ジャーニー改修の安全ルール（必須）

既存 CJO ジャーニーを変更する依頼では、**例外なく**このファイルの手順に従う。
本番ジャーニー（以下「本番」）に変更を入れる前に、テストジャーニーで利用者に確認してもらう。

## 0. 前提となる既知の挙動

| 挙動 | 影響 | このSkillの対応 |
|---|---|---|
| **API（REST PATCH/PUT）は不正な値・構造でも受け付けることがある** | 受け付けた後に Console 表示や実行が壊れ、ジャーニーが使えなくなる | 本番に API を直接当てない。同じペイロードを先にテストジャーニーへ当てて検証する。送信前に必ず GET バックアップ |
| **エントリー条件を変更するとジャーニーのバージョンが上がる** | 旧バージョンでジャーニー内にいたユーザーが**ステージ途中で抜ける** | エントリー条件に触れる変更は事前に判定し、影響人数を示して明示承認を取る。代替案も提示 |
| `tdx journey push` は**フォルダ（= YAML の置き場所）+ ジャーニー名**で既存を探す。アクティベーションは名前で照合 | YAML を別フォルダに置く・名前を変えると**別ジャーニーが新規作成**される（2バージョン問題の主因）。接続先変更で別アクティベーションIDになる | 本番 YAML は pull した場所から動かさない。push 後に URL・バージョン・アクティベーションIDを必ず検証（journey-build.md Step 5） |
| `tdx journey validate` は API 制約の一部を検査しない | validate が通っても push / 実行で失敗 | dry-run と Console 目視を必ず挟む |

## 1. 全体の流れ

```
① 本番の現状を取得・バックアップ（読み取りのみ）
② 変更内容を整理し、エントリー条件への影響を判定
③ テストジャーニー test_v<N>_<本番名> を新規作成（本番と同じ構造 + 変更）
④ テストジャーニーで検証 → 利用者に確認してもらう（Console URL を提示）
⑤ 利用者の承認後に本番へ反映（version create → 同じ変更 → dry-run → push）
⑥ 本番の反映確認。テストジャーニーの扱い（残す / 削除）を利用者に確認
```

③④を飛ばしてよいのは、利用者が**その回に限り明示的に**「テストジャーニー不要」と指示した場合だけ。その場合もエントリー条件の判定（②）と API の事前バックアップは省略しない。

## 2. ① 本番の現状取得

```bash
mkdir -p ./backups/<YYYYMMDD>
tdx journey view "<本番名>" --include-stats
tdx journey versions "<本番名>"
tdx journey pull "<本番名>"                                   # segments/<ps>/<journey>.yml
cp segments/<ps>/<journey>.yml ./backups/<YYYYMMDD>/<journey>.prod.yml
tdx journey activations "<本番名>" --json > ./backups/<YYYYMMDD>/<journey>.activations.json
python3 scripts/latest_activations.py ./backups/<YYYYMMDD>/<journey>.activations.json
tdx journey stats "<本番名>"                                  # size = 現在ジャーニー内の人数
```

## 3. ② エントリー条件への影響判定

次のどれかに当たれば「**エントリー条件変更あり**」とする:

- ステージ1の `entry_criteria`（セグメントの差し替え・名前変更）
- `entry_criteria` が参照する埋め込みセグメントの `rule` の変更（2ステージ目以降は前ステージの milestone が entry になるので、**milestone セグメントの変更も含める**）
- `reentry` モードの変更
- 判断に迷う変更（ゴール、ステージの追加・削除・並べ替えなど）も「あり」扱いで利用者に確認

判定は pull した本番 YAML とテスト用に編集した YAML を突き合わせて行い、該当箇所を差分で示す。

「あり」の場合、利用者へ必ず次を伝えて `AskUserQuestion` で承認を取る:

> この変更はエントリー条件に関わるため、本番ジャーニーのバージョンが上がります。
> 現在ジャーニー内にいる **N 人**（ステージ別: Stage1 a人 / Stage2 b人 …）は、ステージの途中でジャーニーから外れます。
> - このまま進める
> - エントリー条件を変えない方法で実現する（代替案）
> - 中止する

ステージ別人数はジャーニーテーブル（journey-monitoring.md）で出す:

```sql
SELECT
  COUNT_IF(intime_stage_0 IS NOT NULL AND outtime_stage_0 IS NULL) AS in_stage_0,
  COUNT_IF(intime_stage_1 IS NOT NULL AND outtime_stage_1 IS NULL) AS in_stage_1,
  COUNT_IF(intime_journey IS NOT NULL AND outtime_journey IS NULL) AS in_journey
FROM cdp_audience_<ps_id>.journey_<journey_id>
```

代替案の例（要件次第で提示）:

| やりたいこと | エントリー条件を変えない方法 |
|---|---|
| 対象から一部を外したい | `exit_criteria` に除外セグメントを追加 / ステージ先頭に decision_point を置いて対象外は end |
| 新しい対象を追加したい | 新規ジャーニーを並行して作り、旧ジャーニーは新規流入を止めて既存ユーザーを最後まで流す |
| 配信条件だけ変えたい | アクティベーション前の decision_point / 条件待ちで制御 |

※ exit_criteria / milestone の変更でもバージョンが上がるか、途中ユーザーがどう扱われるかは DEMO 環境で検証して known-issues.md に追記する（未検証の間は「上がる可能性あり」として同様に確認を取る）。

## 4. ③ テストジャーニーの作成

### 命名

`test_v<N>_<本番名>`

- `<本番名>` は本番ジャーニー名そのまま（例: 本番 `hoge` → `test_v1_hoge`）。
- `N` は未使用の最小番号。既存を確認して決める:

```bash
tdx journey list "test_v*_<本番名>"
```

- 同じ改修でテストをやり直す場合は番号を上げる（`test_v2_hoge`）。前のテストは上書きしない。

### 作り方

1. 本番 YAML から生成する（**本番 YAML と同じフォルダ**に出力 → Console でも同じフォルダに作られる）:

```bash
python3 scripts/clone_test_journey.py segments/<ps>/<folder>/<journey>.yml --version <N>
# → segments/<ps>/<folder>/test_v<N>_<journey>.yml
```

   スクリプトが行うこと（PyYAML が無い環境では同じ内容を手作業で行う。スクリプトがチェックリストを表示する）:
   - `name:` → `test_v<N>_<本番名>`
   - トップの `id` / `bundle_id` / `bundle_name` / `version` / `version_number` を削除（`folder_id` は残す）
   - `journeys:` は `latest: true` の1エントリーだけ残し、`id` / `version` / `version_number` / `latest` を削除、`state: draft`
   - `stages[].id`、`steps[].uuid`、ABテストの `variants[].id` と `unique_id` を削除
2. 埋め込みセグメント・アクティベーションは本番と同じ定義のまま（テスト側に別物として作られる）。`ref:` セグメントは他ジャーニー由来なのでそのまま参照してよい。
   - アクティベーションの `name` が本番と同じでも、照合はジャーニー単位の想定。**DEMO で本番側のアクティベーションが変わらないことを確認するまで**、push 後に本番の `tdx journey activations` も取得して変化が無いことを確かめる。
3. 依頼された変更をこのファイルに入れる。
4. **配信事故の防止**（必ず利用者に確認）:
   - テストジャーニーは**draft のまま**。launch / resume / run はしない。
   - 実際に送信して確認したい場合のみ、エントリー条件にテスト受信者（社内アドレス等）だけに絞る条件を追加し、アクティベーション先をテスト用 AOC に向ける。どちらも利用者の明示指示がある時だけ。
5. 検証して push:

```bash
tdx journey validate segments/<ps>/test_v<N>_<本番名>.yml
tdx journey push segments/<ps>/test_v<N>_<本番名>.yml --dry-run    # 「新規作成」になっていること
# preview_journey でフローを表示
tdx journey push segments/<ps>/test_v<N>_<本番名>.yml --yes
tdx journey list "test_v<N>_<本番名>"
tdx journey view "test_v<N>_<本番名>"
```

dry-run が本番ジャーニーへの更新を示したら**即中止**（名前の書き換え漏れ）。

6. API でしか設定できない項目（ストリングビルダー、接続先変更など）は、**テストジャーニーのアクティベーションIDに対して**先に実行する:

```bash
python3 scripts/cdp_api.py patch /entities/journeys/<TEST_JOURNEY_ID>/activations/<TEST_ACT_ID> --body body.json      # dry-run
python3 scripts/cdp_api.py patch ... --execute     # 承認後
python3 scripts/cdp_api.py get /entities/journeys/<TEST_JOURNEY_ID>/activations/<TEST_ACT_ID>   # 反映確認
```

その後 Console でテストジャーニーが開けること・アクティベーション設定が正しく表示されることを確認する（**API が不正値を受け付けて壊れていないかの確認**）。

## 5. ④ 利用者による確認

次を提示し、Console で見てもらう:

- テストジャーニーの Console URL
- 本番 YAML との差分（変更点のみ）
- エントリー条件判定の結果と影響人数
- API で変更した項目と、変更前後の値

`AskUserQuestion`: 「テストジャーニーの内容で本番に反映してよいですか？」— 反映する / 修正する（→ test_v<N+1> で再作成）/ 中止する

## 6. ⑤ 本番への反映（承認後のみ）

1. `tdx journey version create "<本番名>" -y`（launched 版を直接上書きしない）
2. `tdx journey pull "<本番名>"` → `latest: true` のエントリーだけに、テストで確認した変更と**同じ差分**を入れる（作り直さない）
3. `tdx journey validate` → `tdx journey push "<本番名>" --dry-run` → 差分がテストと一致することを確認
4. `tdx journey push ... --yes`
5. API 変更は、テストで成功したペイロードの ID 部分だけを本番の最新アクティベーションIDに置き換えて、dry-run → 承認 → 実行
6. 新バージョンは draft のまま。launch は利用者が Console で行う（Skill からは実行しない）

## 7. ⑥ 反映確認と後片付け

- journey-monitoring.md「改修後の反映チェック」を実施
- テストジャーニーは残すか削除するかを利用者に確認（削除は Console。Skill からは削除しない）
- `cjo-engage-memo.yml` の `journeys` と `decisions_log` に、テスト名・承認日・エントリー条件判定を記録
