# Engage Studio 契約確認・セットアップ

CJO から Engage Studio にメールを流すために必要な構成を確認・作成する。
確認は読み取りのみ。作成・割当は**計画を見せて承認を得てから**1つずつ実行し、直後に show / list で検証する。

```
[送信ドメイン（DNS認証）] ─┐
[送信者プロファイル]  ──────┤
                          ├─ [Engage ワークスペース] ─ [Always-On Campaign + テンプレート]
[親セグメント] ── attach ──┘                                     ▲
                                                                 │ always_on_campaign_id
[CDP コネクション treasure_engage_v1] ── ジャーニーのアクティベーション
```

## 1. 契約有無の判定（読み取りのみ）

tdx には「Engage 未契約」を示す専用エラーが無い。次のシグナルを組み合わせて判定し、**根拠と一緒に**報告する。

```bash
tdx --version
tdx status
tdx engage workspaces                       # S1
tdx connection list | grep -i engage        # S2（type: treasure_engage_v1 / treasure_engage）
tdx delivery senders                        # S3
tdx engage always-on-campaigns              # S4
```

| 結果 | 判定 | 次の行動 |
|---|---|---|
| S1 でワークスペースが1件以上取得できる | **契約あり** | 2. の棚卸しへ |
| S1 が空・S2〜S4 も無し | **未契約 または 未セットアップ**（区別できない） | 利用者に契約状況を確認。「契約済み・未構築」ならセットアップへ |
| S1 が 401 / 403 | **権限不足の可能性**（未契約とは断定しない） | 利用者の権限（Engage 利用権限・管理者）を確認。認証切れなら再認証を案内 |
| S1 がネットワーク / 5xx エラー | **判定不能** | 時間をおいて再実行 |

- 1回の 403 だけで「未契約」と結論しない。
- 判定結果は `cjo-engage-memo.yml` の `engage_studio.contract_status` と `evidence` に日付付きで残す。
- **未契約の場合はセットアップに進まない**。CJO のアクティベーションは既存の他コネクション（SFMC など）を使う設計を提案する。
- 実際のエラーメッセージは DEMO で記録し、known-issues.md に追記する。

## 2. 現状の棚卸し（契約ありの場合）

```bash
tdx engage workspaces
tdx engage workspace show "<ws>" --full --json > /tmp/ws.json   # 割当済み親セグメント・ドメインなど
tdx delivery senders --workspace "<ws>"                         # 送信者プロファイル ID
tdx engage templates --workspace "<ws>"   # 失敗する場合は tdx engage workspace use "<ws>" の後に tdx engage templates
tdx engage always-on-campaigns --workspace "<ws>"
tdx connection list                                             # treasure_engage_v1 のコネクション名
tdx engage media ls                                             # DAM（画像）
```

報告表:

| 項目 | 状態 | 値 |
|---|---|---|
| ワークスペース | ✅ / ❌ | 名前・ID |
| 親セグメント割当 | ✅ / ❌ | 割当済みの親セグメント（`applicableParentSegments`） |
| 送信ドメイン割当 | ✅ / ❌ | ドメイン |
| 送信者プロファイル | ✅ / ❌ | sender ID・From |
| CDP → Engage コネクション | ✅ / ❌ | コネクション名（type `treasure_engage_v1`） |
| Always-On Campaign | 件数 | ジャーニーで使う AOC 名・ID |
| テンプレート | 件数 | — |

## 3. セットアップ手順（足りないものだけ。各手順で承認 → 実行 → 検証）

### 3-1. ワークスペース

```bash
tdx engage workspace create --name "<ws>" --description "<用途>"
tdx engage workspace show "<ws>" --full --json
tdx engage workspace use "<ws>"            # 以降の Engage コマンドのコンテキスト
```

### 3-2. 親セグメントの割当

```bash
tdx engage workspace parent-segment attach "<親セグメント名>" --workspace "<ws>"
tdx engage workspace show "<ws>" --full --json      # applicableParentSegments に出ること
```

割当て先の親セグメントの列がテンプレートの差し込み変数になる（engage-email.md）。

### 3-3. 送信ドメインの割当

```bash
tdx engage workspace email-domain attach "<domain>" --workspace "<ws>"
```

- tdx は送信ドメインの**一覧と割当**のみ。ドメインの新規登録・DNS（SPF / DKIM / DMARC など）の認証は **Console で行う**。必要なDNSレコードは Console の画面で確認するよう案内し、レコード値を推測で書かない。

### 3-4. 送信者プロファイル

```bash
tdx delivery senders --workspace "<ws>"
```

- tdx は**一覧のみ**。作成は Console。作成後に ID を取得して `cjo-engage-memo.yml` の `sender_id` に記録する。
- テンプレート / キャンペーン / AOC の YAML では `email.sender_id` に設定する（旧資料の `connector.email_sender_id` ではない）。

### 3-5. CDP → Engage コネクション

```bash
tdx connection list
tdx connection schema treasure_engage_v1      # ジャーニーの connector_config に書けるキー
```

- コネクションが無い場合は Console（Integrations）で作成してもらう。tdx に作成コマンドは無い。
- V0（`treasure_engage`）と V1（`treasure_engage_v1`）がある。新規は V1 を使う。

### 3-6. Always-On Campaign（ジャーニーの配信先）

engage-email.md の AOC 手順で作成する。ジャーニーのステージごとに AOC を分けるか1つにまとめるかを利用者に確認する。

### 3-7. 配信準備チェック

```bash
tdx engage campaign readiness <campaign-or-aoc.yaml> --workspace "<ws>"
```

確認内容: ワークスペースに送信ドメインが割当済みか / `email.sender_id` が設定されているか / 送信者がワークスペースで使えるか / 送信者のドメインが割当済みか。メールのみ対応。

## 4. 完了報告

2. の表を更新して再提示し、Console でしかできない残作業（DNS 認証、送信者作成、コネクション作成、UTM 設定など）を一覧にする。
