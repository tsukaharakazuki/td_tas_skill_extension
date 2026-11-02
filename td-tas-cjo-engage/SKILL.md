---
name: td-tas-cjo-engage
description: 'Use when creating, updating, fixing, or reviewing Treasure Data CDP Customer Journey Orchestration (CJO) journeys in Treasure AI Studio, especially ones that send email via Engage Studio. Checks whether the account has Engage Studio and, if so, inventories and sets up workspace, parent segment, send domain, sender, Engage V1 connection, Always-On Campaigns and templates. Builds new journeys step by step; updates existing journeys only through a mandatory test journey (test_v<N>_<name>) with entry-criteria impact checks. Covers journey/segment YAML, Engage activations, coupon string builder and column mapping via API, template variables from the parent segment schema, and HTML-to-plaintext generation and checks. Triggers on 「CJO作成」「ジャーニー作成」「ジャーニー改修」「アクティベーション設定」「Engage Studioを契約しているか」「Engageのセットアップ」「AOC」「クーポンコード設定」「プレーンテキストを作成」「HTMLとテキストの整合性」「journey push が効かない」, Engage console URLs, or TD / トレジャーデータ with journeys or Engage.'
---

# TD CJO × Engage Studio（Treasure AI Studio）

Treasure AI Studio で CDP ジャーニー（CJO）を新規作成・改修し、配信チャネルとして Engage Studio を使う。
回答は利用者の言語で行う。外部 Skill のインストールを前提にしない（必要な知識は `references/` に同梱）。

## 1. 最初に必ず守ること

1. **既存ジャーニーの改修は、必ずテストジャーニー `test_v<N>_<本番名>` を新規作成して利用者に確認してもらってから本番に反映する**。手順は [journey-update-safety.md](references/journey-update-safety.md)。省略できるのは利用者がその回に限り明示的に不要と言った時だけ。
2. **エントリー条件に関わる変更はバージョンが上がり、ジャーニー内のユーザーがステージ途中で抜ける**。影響人数を示して明示承認を取る。
3. **REST API は不正な値でも受け付けてジャーニーを壊すことがある**。本番に直接当てない。テストで先に実行し、必ず GET バックアップ（`scripts/cdp_api.py` は dry-run 既定）。
4. **配信が始まる操作は実行しない**: `tdx journey resume` / `run`、`tdx engage always-on-campaign launch` / `resume`、`tdx engage campaign launch`、Console での launch。必要なら `--dry-run` で対象・件数・連携先を平易に説明し、明示承認を得た場合のみ。
5. **削除しない**: ジャーニー、セグメント（`tdx sg push --delete` 禁止）、テンプレート、AOC、DAM 画像。
6. **raw API でセグメントを書き戻さない**（rule が消える）。子セグメントは `tdx sg push` / `tdx sg move`、埋め込みは journey YAML。
7. **推測しない**: 親セグメント名、列名と値、コネクション名、connector_config のキー、AOC / workspace / sender の ID はコマンドで確認する。親セグメントIDは `tdx ps list` に出ないので、URL のIDから推測せず名前を聞く。
8. 書き込みは **validate → `--dry-run` → preview → 承認 → 実行 → 再取得で検証** の順。Studio の `preview_journey` / `preview_segment` / `preview_engage_template` / `preview_engage_campaign` を使う。
9. tdx のプロファイル・サイトを切り替えない。

## 2. 依頼の振り分け

| 依頼 | 読むファイル |
|---|---|
| Engage Studio を契約しているか / セットアップ状況 / 足りない設定を作る | [engage-setup.md](references/engage-setup.md) |
| テンプレート・Always-On Campaign・One-Off Campaign を作る / 差し込み変数を調べる | [engage-email.md](references/engage-email.md) |
| プレーンテキストを作る / HTML とテキストの整合性チェック | [plaintext.md](references/plaintext.md) |
| 新しいジャーニーを作る | [journey-build.md](references/journey-build.md) |
| 既存ジャーニーを直す・ステージや分岐を変える・配信先を変える | [journey-update-safety.md](references/journey-update-safety.md)（必須）→ 必要に応じ下記 |
| アクティベーション（Engage 連携、クーポン固定値、列名変更、スケジュール） | [activation-engage.md](references/activation-engage.md) |
| セグメント条件（未購買、除外、ビヘイビア集計、エラーコード） | [segment-rules.md](references/segment-rules.md) |
| ジャーニー YAML の文法・validate エラー・フロー制御 | [journey-validation.md](references/journey-validation.md) |
| 現状確認・反映確認・ジャーニーテーブルの集計 | [journey-monitoring.md](references/journey-monitoring.md) |
| 「push したのに反映されない」など不可解な挙動 | [known-issues.md](references/known-issues.md) |

ジャーニーで Engage を使う依頼では、最初に engage-setup.md 1. で契約と前提（ワークスペース・送信者・AOC・コネクション）を確認する。前提が揃っていなければ、ジャーニー作業の前にセットアップするか、Engage 以外の配信先にするかを利用者に確認する。

## 3. 開始時の確認

```bash
tdx --version          # 2026.10 未満なら AOC の YAML 操作は使えない（engage-email.md 3.）
tdx status             # 認証・サイト
```

- Console URL を受け取ったら `python3 scripts/parse_console_url.py "<URL>"` で ID を取り出す（Engage: `/app/es/<workspace>/em|ooc|aoc/<id>`）。
- 作業フォルダの `cjo-engage-memo.yml` を読む。無ければ [templates/project-memo.yml](templates/project-memo.yml) から作り、確認した名前・ID・合意事項を追記していく（秘密情報は書かない）。
- 作業用ファイルは作業フォルダ内（`segments/`, `templates/`, `backups/` など）に置き、`/tmp` だけに残さない。

### 認証（Treasure AI Studio）

`tdx` が `Authentication failed` を返したら、`mcp__tas__request_credential` で `td_api_production_aws` を取得し、以降のコマンドの先頭で設定する:

```bash
export TDX_ACCESS_TOKEN=$(curl -sf http://172.30.0.1:18080/credentials/td_api_production_aws)
export TDX_SITE=us01      # 対象サイト（jp01 等）に合わせる
```

`scripts/cdp_api.py` は `TDX_ACCESS_TOKEN` → `TDX_ACCESS_TOKEN_FILE` → `TD_API_KEY` の順で資格情報を読む。トークンを画面・ファイル・メモに出力しない。
`tdx api` は既定で無効。有効化は利用者の判断なので、Skill から有効化しない（REST が必要な時は `cdp_api.py`）。

## 4. 同梱スクリプト（Python 標準ライブラリ。`python3 -I` で実行）

| スクリプト | 用途 |
|---|---|
| `parse_console_url.py` | Console URL からサイト・workspace・テンプレート / キャンペーン / ジャーニー ID |
| `clone_test_journey.py` | 本番 YAML → `test_v<N>_<名前>` の新規ジャーニー YAML（ID 類を除去。PyYAML 必要、無ければ手順を表示） |
| `latest_activations.py` | `tdx journey activations --json` から名前ごとの最新ID・重複・Engage 設定 |
| `cdp_api.py` | CDP REST の GET / PATCH / PUT。書き込みは GET バックアップ + dry-run 既定、`--execute` で送信 |
| `html_extract.py` | メール HTML の本文・画像（vision 要否）・リンク（UTM 付与）・Liquid |
| `check_mail_consistency.py` | HTML / TXT / 件名の日付・金額・割引・URL・文の差分 |

## 5. 報告の形

- 何を確認し（コマンド）、何が分かり、何を変えたか / 変えていないかを分けて書く。
- 変更提案は「変更前 → 変更後」の差分で示す。ID・名前・件数は実測値。
- 承認を取る時は `AskUserQuestion` を使い、選択肢に「中止」を含める。
- 最後に、Console でしかできない残作業と、利用者が行う launch などの操作を一覧にする。
- 想定と違う挙動に出会ったら、報告に含め、known-issues.md への追記を提案する。
