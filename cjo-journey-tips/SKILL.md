---
name: cjo-journey-tips
description: 'Use when creating, editing, or troubleshooting Customer Journey Orchestration (CJO) journeys and activations on Treasure Data. Covers tdx journey CLI vs REST API usage, common errors, activation settings, segment conditions, and coupon code/string builder configurations. Triggers on: "ジャーニーを作成", "アクティベーション設定", "CJO修正", "journey push が効かない", "journey activation", "クーポンコード設定", "ストリングビルダー", "Engage Studio", "always-on campaign", or any request to build/edit a TD journey.'
---

# CJO ジャーニー作成・修正 Tips

## 概要

Treasure Data の CJO ジャーニーを `tdx journey` CLI と REST API を組み合わせて操作するための汎用ガイド。
CLI の制限や仕様上の挙動（落とし穴）を回避し、安全かつ迅速にジャーニーの構築・修正を行うためのノウハウをまとめています。

---

## 1. tdx CLI vs REST API の使い分け

| やりたいこと | 推奨手段 | 理由 |
|---|---|---|
| ジャーニー構造の作成・変更（ステージ、条件、分岐） | **tdx journey push** | YAML管理できるため、Gitによるバージョン管理や差分比較が容易 |
| アクティベーションの接続先・カラム・スケジュール変更 | **REST API (PATCH)** | CLIのpushはアクティベーション実体を更新しない場合があるため |
| ストリングビルダー（固定文字列）の設定 | **REST API (PATCH)** | YAMLのvalidateでエラーになる（StringExpressionが未対応など）ため |
| セグメント条件の除外ロジック（NOT IN相当） | **REST API (PUT)** | YAMLの `excluded: true` が反映されないことがあるため |
| AOC（Always-On Campaign）の設定 | **REST API** | CLIにpull/pushコマンドが存在しないため |

---

## 2. tdx journey push の落とし穴

### 問題: pushが別バージョンを作成し続ける（2バージョン問題）

- pushのレスポンスURLが `/e/XXXXX` で、コンソールのURLと異なる場合は、**コンソール側のジャーニーとは別のジャーニーが新規作成されている**可能性があります。
- **確認方法**:
  
```bash
# pushのURLを確認
tdx journey push xxx.yml --yes 2>&1 | grep "https"
# → 出力されるURLが、コンソール上のジャーニーURLと一致するか確認

# バージョン数を確認
tdx journey versions "[ジャーニー名]" --parent-segment "[親セグメント名]"
# latest:false のバージョンがあれば、重複して作成されている可能性があります
```

- **解決策**: コンソール上で不要な重複ジャーニーを削除し、YAML側の名称や対象の親セグメント設定を見直してから再度 `push` します。

### 問題: pushが「0 changed / 0 unchanged」と表示されても変更が反映されない

- `tdx journey activations` APIが返すデータは、**旧バージョンのアクティベーション情報**の場合があります。
- YAML（ローカル）の状態と、CDP上の実際のアクティベーション状態が乖離していることがあります。
- **解決策**: 状態の確認はYAMLのpull結果を過信せず、必ずAPI経由（または `tdx` コマンド）で最新の実態を取得して確認してください。

```bash
# API経由で実際のアクティベーション一覧と各接続先・IDを抜き出して確認するスクリ例
tdx journey activations "[ジャーニー名]" --parent-segment "[親セグメント名]" --json > /tmp/acts.json
python3 -c "
import json
with open('/tmp/acts.json') as f: data = json.load(f)
acts = data if isinstance(data,list) else data.get('data',[])
# 名前ごとに最新IDのみ取得
latest = {}
for a in acts:
    attrs = a.get('attributes',a)
    name = attrs.get('name','')
    aid = int(a.get('id','0'))
    if name not in latest or aid > int(latest[name]['id']):
        latest[name] = {'id':str(aid),'conn':attrs.get('connectionId'),'allCols':attrs.get('allColumns')}
for name,v in sorted(latest.items()):
    print(f\"ID:{v['id']} conn:{v['conn']} allCols:{v['allCols']} | {name}\")
"
```

### 問題: 特定のパス/ステージのアクティベーションしか更新されない

- `tdx journey push` はアクティベーション名（name）でマッピングを行っています。
- **接続先（connectionId）が変わる場合、新しいアクティベーション（新しいID）が作成されます**。コンソール上のジャーニーが古いIDを参照し続けている場合、変更が反映されません。
- **解決策**: REST API（PATCH）を用いて、変更したい既存のアクティベーションID（`activationStepId`）に対して直接パラメータを更新します。

---

## 3. REST API でアクティベーションを更新する

### エンドポイント
```
PATCH https://api-cdp.treasuredata.com/entities/journeys/{journeyId}/activations/{activationStepId}
```

### 認証
```bash
TOKEN=$(cat "$TDX_ACCESS_TOKEN_FILE")
```

### 基本的なリクエスト例（Engage Studio + 全カラム + 固定値クーポンコード）
```python
import json, os, urllib.request

token = open(os.environ['TDX_ACCESS_TOKEN_FILE']).read().strip()

payload = {
    "type": "journeyActivationStep",
    "id": "[ACTIVATION_STEP_ID]",
    "attributes": {
        "activationParams": {
            "name": "[アクティベーション名]",
            "connectionId": "[CONNECTION_ID]",     # 例: 111111 (Engage Studio V1)
            "allColumns": True,                    # すべてのカラムを出力する場合
            "columns": [
                # email_raw を email として出力
                {"column": "email", "source": {"column": "email_raw"}},
                # ストリングビルダー（固定文字列）の設定例（例: クーポンコードの固定値）
                {"column": "coupon_code", "source": {
                    "string": "$1",
                    "parameters": [{"type": "String", "string": "[COUPON_CODE_OR_PREFIX]"}]
                }}
            ],
            "scheduleType": "daily",
            "scheduleOption": "11:00:00",          # 配信時刻
            "timezone": "Asia/Tokyo",
            "notifyOn": ["onFailure"],
            "emailRecipients": [[NOTIFY_USER_ID]],  # 例: 999999 (通知先ユーザーID)
            "connectorConfig": {
                "campaignType": "email",
                "workspaceId": "[WORKSPACE_ID]",    # EngageワークスペースID
                "alwaysOnCampaignId": "[AOC_ID]",   # 常時稼働キャンペーン（AOC）ID
                "jsonColumns": None,
                "batchSize": 1000,
                "threadCount": 1
            }
        }
    },
    "relationships": {}
}

req = urllib.request.Request(
    f"https://api-cdp.treasuredata.com/entities/journeys/{JOURNEY_ID}/activations/{ACTIVATION_STEP_ID}",
    data=json.dumps(payload).encode(),
    method="PATCH",
    headers={
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/vnd.treasuredata.v1+json"
    }
)
with urllib.request.urlopen(req) as resp:
    result = json.loads(resp.read())
```

---

## 4. セグメント条件設計の注意点

### 「未購買」「特定の経験なし」の条件における落とし穴

**間違い**: RFMテーブルや購買履歴ビヘイビアテーブルで、直接 `frequency_all = 0` や `buy_count = 0` を条件にする。
- 多くの場合、RFMや購買系のビヘイビアテーブルには**購買実績があるユーザーのデータ（レコード）しか存在しません**。
- レコード自体が存在しないため、`frequency_all = 0` でフィルタリングしても誰も抽出されません。

**正しい**: 「購買が1回以上（`frequency_all >= 1`）存在するユーザー」を**除外（Exclude）**する、あるいはカウントが1未満であることを条件にします。
- APIで設定する場合、カウント集計した値に対して `operator: {type: "Less", rightValue: 1}`（COUNT < 1）を使用します。

```python
# 正しいRFM未購買（購買実績なし）の条件設定例
rfm_condition = {
    "type": "Value",
    "arrayMatching": "any",
    "exclude": False,
    "leftValue": {
        "aggregation": {"type": "Count"},
        "filter": {
            "type": "And",
            "conditions": [{
                "type": "Column",
                "column": "frequency_all",
                "operator": {"not": False, "rightValue": 1, "type": "GreaterEqual"}
            }]
        },
        "source": {"name": "[BEHAVIOR_TABLE_NAME]"} # 例: behavior_rfm_table
    },
    "operator": {"not": False, "rightValue": 1, "type": "Less"}  # COUNT < 1
}
```

### セグメント条件設計前に必ず確認するチェックリスト

要件定義やエクセル等の設計書から設定を起こす前に、以下の点を確認・ヒアリングします：

1. **「F0」「未購買」「初回購入促進」の条件**
   - 「対象のビヘイビアテーブルには購買実績のあるユーザーしかレコードが存在しない可能性が高いです。その場合、"テーブルにレコードが存在するユーザーを全体から除外する"（またはCOUNT < 1）というロジックで実装してもよいですか？」と確認。
2. **「会員登録からN日経過」などの期間条件**
   - ビヘイビア（行動履歴）として判定するのか、マスター（アトリビュートカラム。例：`registerdatetime_duration` など）で判定するのかを確認。
3. **「購買N回以上」「Fx転換」**
   - ジャーニー上の各配信ステージ（F1向け、F2向けなど）と、クーポン・施策側の対象セグメント定義（例: F0転換、F1転換、F2転換）の対応関係を確認。
4. **エントリー条件やステージ遷移条件での「除外（Excluded）ロジック」**
   - YAMLの `excluded: true` は `tdx sg validate` ではエラーになりませんが、反映されない不具合が一部報告されています。安全のため、APIで直接 `operator: {type: "Less", rightValue: 1}` などのロジックに置き換えて設定することを検討します。

---

## 5. クーポンコード設定（ストリングビルダー）

### 施策リスト上の種別とジャーニー分岐の対応関係（例）

| クーポン/施策の種別 | 対応するジャーニー分岐（ターゲット） | 説明 |
|---|---|---|
| F0向け（F1転換） | **ジャーニー対象外**（または専用の初回購入促進ジャーニー） | 新規登録後、未購買ユーザー向けの配信 |
| F1向け（F2転換） | ジャーニーの「F1（1回購入者）」ステージ | 1回購入したユーザーに対して2回目の購入を促す |
| F2以上（F3転換） | ジャーニーの「F2（2回購入者）」または「F3以上」ステージ | 複数回購入ユーザーへのリピート促進（同じクーポンを配布する場合など） |

- **確認ポイント**: 設計書で「F0クーポン」といった指定がある場合、対象のジャーニー（リピート促進用など）に該当ステージがあるか、あるいは新規専用ジャーニーが別途必要かを確認。

### ストリングビルダー（固定値の埋め込み）の正しい設定方法

YAMLの `string_columns` は `pull` した際に形式が変わったり不安定になったりするため、**API経由で設定することを推奨**します。

```python
# columns配列内にStringExpression形式でパラメータを指定して追加
{"column": "coupon_code", "source": {
    "string": "$1",
    "parameters": [{"type": "String", "string": "[COUPON_CODE_OR_PREFIX]"}]
}}
```

---

## 6. Always-On Campaign (AOC) の操作

### CLIでできること / できないこと（Engage Studio連携時）

| 操作 | CLI | API |
|---|---|---|
| AOC一覧取得 | `tdx engage always-on-campaigns --workspace [WORKSPACE]` | ✔ |
| AOC作成（基本情報の登録） | `tdx engage always-on-campaign create` | ✔ |
| AOC作成（テンプレート紐付け） | ❌ （pull/pushコマンド未対応） | コンソールUIで手動設定 |
| AOC作成（UTMパラメータ設定） | ❌ | コンソールUIで手動設定 |

### AOCのフォルダ管理問題
- `tdx journey push` で新規ジャーニーを作成する際、YAMLに `folder: [フォルダ名]` を指定しても実際にはコンソール上でフォルダに反映されないことがあります。
- **解決策**: ジャーニー作成後、CDPコンソールUI上でドラッグ＆ドロップして適切なフォルダへ移動させてください。

---

## 7. プロジェクト固有の設定値テンプレート（参照・管理用）

新しくプロジェクトやクライアント向けにジャーニーを設定する際は、以下の構成案をコピーしてローカルのメモやWikiに貼り付け、IDなどを管理してください。

```yaml
# ==============================================================================
# [プロジェクト名/クライアント名] CJOジャーニー管理用設定値メモ
# ==============================================================================

# 1. CDP基本情報 (Parent Segment / Audience)
parent_segment: "[親セグメント名] (例: すべての顧客セグメント)"
audience_id: [AUDIENCE_ID] (例: 123456)

# 2. Engage ワークスペース情報
workspace: "[Engageワークスペース名] (例: メインワークスペース)"
workspace_id: "[EngageワークスペースID] (例: 01997f0c-xxxx-xxxx-xxxx-xxxxxxxxxxxx)"

# 3. コネクション情報 (Engage V1 Connection)
connection_id: "[CONNECTION_ID] (例: 111111)"

# 4. 常時稼働キャンペーン (AOC) ID一覧
# (例: 休眠復帰・経過日数別の配信など、複数AOCがある場合にメモ)
aoc_ids:
  stage_1: "[AOC_ID_1] (例: 019f5fbc-xxxx-xxxx-...)"
  stage_2: "[AOC_ID_2]"
  stage_3: "[AOC_ID_3]"

# 5. ジャーニー ID一覧
journey_ids:
  reengagement: [JOURNEY_ID_1] (例: 222222)
  onboarding: [JOURNEY_ID_2] (例: 333333)

# 6. エラー・失敗時の通知先メールアドレス
email_recipients: [[RECIPIENT_USER_ID_1], [RECIPIENT_USER_ID_2]] # 例: [999999]
```

---

## 8. 推奨開発・更新ワークフロー

### 新規ジャーニー作成フロー
1. ローカルでジャーニー定義YAMLを作成 → `tdx journey validate` で構文チェック。
2. `tdx journey push` でCDPへ適用。
3. pushのURLがコンソールのURLと一致しているか（別ジャーニーが作られていないか）確認。
4. カラムマッピングやスケジュールなどの詳細なアクティベーション設定は、REST API PATCH（前述のPythonスクリプトなど）を用いて上書き。
5. フォルダ移動はCDPコンソールUIから手動で実施。

### 既存ジャーニーのアクティベーション修正フロー
1. `tdx journey activations` を実行して、APIが現在認識している最新状態を確認（ローカルのYAMLを過信しない）。
2. 修正対象のアクティベーションIDを特定（**名前が同じで複数存在する場合は、IDが最も大きいものが最新です**）。
3. 指定したアクティベーションIDに対し、REST API PATCHで直接更新。
4. 更新後、再度 `tdx journey activations` もしくはコンソール上で期待通り反映されているか確認。

### セグメント条件の修正フロー
1. 現在のセグメント設定（rule）を、GET `/entities/segments/{segmentId}` で取得。
2. 取得したPython dict等のJSON構造のルール部分（`rule`）を書き換える。
3. PUT `/audiences/{audienceId}/segments/{segmentId}` で更新。
4. CDPコンソール上で、変更されたセグメントの「生成SQL」などを目視して意図通りの条件になっているか最終確認。
