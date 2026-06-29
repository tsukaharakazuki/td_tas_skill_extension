---
name: excel-to-td-upload
description: Use when the user wants to upload an Excel file (.xlsx) with multiple sheets to Treasure Data (TD). Triggers on: "ExcelをTDにアップロード", "ExcelをTreasure Dataに取り込む", "スプレッドシートをTDに", "エクセルをインポート", "シートごとにテーブルに", "Excel upload to TD", "upload Excel to Treasure Data", or any request to import a multi-sheet Excel file into a TD database/table.
---

# Excel → Treasure Data Upload

ExcelファイルをTreasure Dataにアップロードする対話型ウィザード。シートごとのテーブル分割、日本語→英語変換、カラム名正規化を自動で行う。

## Overview

1. Excelファイルのシート構造を調査する
2. アップロード設定をヒアリングする（**必ずテキストで質問し、回答を待ってから次へ進む**）
3. テーブル名・カラム名を正規化する（日本語→英語、TD命名規則に準拠）
4. `td table:import --json` を使ってデータを投入する

---

## Step 1: Excelファイルの調査

ユーザーが提供したExcelファイルを `openpyxl` で読み込み、シート一覧・先頭行・行数を把握する。

```python
import openpyxl

wb = openpyxl.load_workbook("path/to/file.xlsx", read_only=True, data_only=True)
for sheet_name in wb.sheetnames:
    ws = wb[sheet_name]
    rows = list(ws.iter_rows(min_row=1, max_row=3, values_only=True))
    first_row = rows[0] if rows else []
    non_null = [c for c in first_row if c is not None]
    second_row = rows[1] if len(rows) > 1 else []
    print(f"[{sheet_name}] カラム数: {len(non_null)}, 1行目: {first_row[:8]}, 2行目: {second_row[:3]}")
```

行数も確認しておく（大容量テーブルの事前把握のため）:

```python
for sheet_name in wb.sheetnames:
    ws = wb[sheet_name]
    all_rows = list(ws.iter_rows(values_only=True))
    non_empty = [r for r in all_rows if any(c is not None for c in r)]
    print(f"[{sheet_name}] 総行数: {len(all_rows)}, 非空行数: {len(non_empty)}")
```

調査結果をユーザーに提示し、空シート・目次シート・旧データシートをスキップ候補として提案する。

---

## Step 2: ヒアリング（AskUserQuestion を使う）

**必ず `AskUserQuestion` ツールを使う。** テキスト文章で質問してはいけない。

### 質問セット A（1回目）: DB名・シート選択

```
質問1: アップロード先のDatabase名は何ですか？
  header: "Database名"
  options:
    - label: "直接入力（Other で入力）"
      description: "既存または新規のDB名を入力してください（例: my_database）"

質問2: どのシートを取り込みますか？
  header: "シート選択"
  options:
    - label: "すべてのシート（推奨）"
      description: "空・目次シートは自動スキップ候補として提示済み"
    - label: "一部のシートだけ（Other で列挙）"
      description: "取り込みたいシート名、またはスキップしたいシート名を入力"
```

### 質問セット B（2回目）: ヘッダー構造・既存データ

Step 1 の調査で 2行ヘッダーのシートが検出された場合のみ質問 3 を追加する。

```
質問3（2行ヘッダーが存在する場合のみ）: 該当シートのヘッダー行はどちらですか？
  header: "ヘッダー行"
  options:
    - label: "2行目をヘッダーとして使う（推奨）"
      description: "1行目がタイトル行、2行目がカラム名のシートに適用"
    - label: "1行目をヘッダーとして使う"
      description: "通常構造のシートに適用"

質問4: 既存テーブルがある場合の扱いは？
  header: "既存データ"
  options:
    - label: "上書き（overwrite）（推奨）"
      description: "既存データを全て削除して新しいデータで置き換える"
    - label: "追記（append）"
      description: "既存データの末尾に追加する"
```

### 質問セット C（3回目）: テーブル名・カラム名変換確認

Step 3 の名前正規化を実施した後、変換案を提示して確認する。

```
質問5: テーブル名・カラム名の変換案を確認してください
  header: "変換確認"
  options:
    - label: "この変換で進める（推奨）"
      description: "（変換案をdescriptionに列挙して提示する）"
    - label: "修正する（Other で入力）"
      description: "変更したい箇所を「元の名前 → 新しい名前」の形式で入力"
```

---

## Step 3: 名前の正規化

TD命名規則: **英数小文字と `_` のみ**（テーブル名・カラム名とも）

### 日本語→英語の変換方針
- Claude自身が意味を解釈して英語に翻訳し、変換案をユーザーに提示して確認を取る
- 確認はテキストで「修正が必要な場合はお知らせください」と添える

### 変換例

| 元の名前 | 変換後 |
|---------|--------|
| 申込日 | application_date |
| 納品日 | delivery_date |
| 店舗名 | store_name |
| 会社ID | company_id |
| ①売上データ | sales_data |
| ②顧客一覧 | customer_list |
| 全店データ（日次） | all_stores_daily |
| スコア推移 | score_trend |
| 平均値 | average |
| ★評価 | star_rating |
| 第１階層 | level_1 |

### 記号・特殊文字の処理
- 全角文字・記号は除去またはアンダースコアに変換
- 先頭が数字の場合は `col_` プレフィックスを付与
- 連続する `_` は1つにまとめる
- 変換後が空文字になる場合は `column_N`（Nは列番号）とする
- **datetime 型のカラム名**（月次・日次データでヘッダーが日付になっている場合）は `date_YYYY_MM_DD` 形式に変換する

```python
def normalize_col_name(raw, col_map, index):
    if raw is None:
        return f"column_{index}"
    s = str(raw).strip()
    if s in col_map:
        return col_map[s]
    if isinstance(raw, datetime):
        return f"date_{raw.strftime('%Y_%m_%d')}"
    import re
    s_clean = re.sub(r'[^\w]', '_', s.lower())
    s_clean = re.sub(r'_+', '_', s_clean).strip('_')
    if not s_clean or s_clean[0].isdigit():
        s_clean = f"col_{s_clean}"
    return s_clean if s_clean else f"column_{index}"
```

---

## Step 4: 固定カラムの付与

すべてのテーブルに以下の2カラムを自動付与する:

| カラム名 | 値 | 説明 |
|---------|-----|------|
| `excel_name` | アップロードしたExcelファイル名（拡張子含む） | どのファイルから来たか |
| `excel_sheet_name` | 元のシート名（翻訳前の原文） | どのシートから来たか |

---

## Step 5: アップロード実装

### ⚠️ pytd は使わない

Treasure Work の OAuth トークン（Bearer）は `pytd` / `tdclient` の urllib3 と互換性がなく動作しない。
**`td table:import --json` コマンドを使う**のが唯一の確実な方法（2026年6月時点）。

### 5-1. 前提確認

```bash
pip3 install openpyxl --quiet
which td   # /usr/local/bin/td などが返ればOK
```

`td` コマンドは `/usr/local/bin/td` に存在する。ただし `td` のデフォルト設定が別アカウント（JP リージョンなど）に向いている場合があるため、**APIキーとエンドポイントを必ず明示指定**する。

```bash
td -k "<TD_API_KEY>" -e https://api.treasuredata.com db:list
```

### 5-2. APIキーの取得

Treasure Work の OAuth Bearer トークンは **書き込み API（Bulk Import 等）に使えない**。
ユーザーに以下を依頼してAPIキーを取得する:

> TDコンソール（https://console.us01.treasuredata.com）→ Settings → API Keys から
> **Write権限のあるAPIキー**をコピーして教えてください。

APIキーの形式: `<account_id>/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`

### 5-3. td コマンドの制限事項

- `td -k <key> -e <endpoint> table:delete` は **DBリスト権限がないと失敗する（exit 1）**
- `td -k <key> -e <endpoint> table:create` も同様にDBリスト権限チェックで失敗することがある
- テーブルの存在確認・削除・再作成は **REST API（curl）で行う**

```python
def ensure_table_exists(database, table_name, api_key, endpoint):
    """REST API でテーブル存在確認（DBリスト権限不要）"""
    import subprocess
    r = subprocess.run(
        ["curl", "-s", "-H", f"Authorization: TD1 {api_key}",
         f"{endpoint}/v3/table/show/{database}/{table_name}"],
        capture_output=True, text=True
    )
    if '"type"' in r.stdout:
        return True   # 存在する
    # 存在しない → td table:create は DBリスト権限チェックあり
    # 代替: REST API で作成
    r2 = subprocess.run(
        ["curl", "-s", "-X", "POST",
         "-H", f"Authorization: TD1 {api_key}",
         f"{endpoint}/v3/table/create/{database}/{table_name}/log"],
        capture_output=True, text=True
    )
    return True
```

> **注意**: テーブル削除（overwrite）は `DELETE /v3/table/delete/` で行えるが、
> **アカウント権限によっては 403 が返る**場合がある。
> その場合はテーブルを削除せず `table:import` で既存テーブルにデータを追加する形になる。
> （初回アップロード時はテーブルが空なので実質 overwrite と同じ）

### 5-4. アップロードスクリプト（確定版）

```python
import openpyxl
import math
import os
import json
import subprocess
import tempfile
import time
import re
from datetime import datetime

EXCEL_PATH = "path/to/file.xlsx"
DATABASE = "target_database"
TD_API_KEY = "<account_id>/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"  # ユーザーから取得
TD_ENDPOINT = "https://api.treasuredata.com"  # US01
# JP: https://api.treasuredata.co.jp
# EU: https://api.eu01.treasuredata.com
EXCEL_FILENAME = os.path.basename(EXCEL_PATH)
NOW_TS = int(time.time())  # 全レコード共通の time 値

# シート名 → (テーブル名, ヘッダー行インデックス(0始まり))
SHEET_CONFIG = {
    "シートA":    ("table_a", 0),
    "シートB":    ("table_b", 0),
    "シートC":    ("table_c", 1),  # 2行目がヘッダーの場合
    # ...
}

# カラム名変換マップ（シートごと）
COLUMN_MAPS = {
    "table_a": {
        "日本語カラム名1": "english_col_name_1",
        "日本語カラム名2": "english_col_name_2",
        # ← 日本語カラムは漏れなく登録する（未登録は normalize_col_name で自動変換）
        # ...
    },
    # ...
}


def clean_value(v):
    """NaN / Inf / Excelエラー値 を None に変換"""
    if v is None:
        return None
    if isinstance(v, float) and (math.isnan(v) or math.isinf(v)):
        return None
    if isinstance(v, str) and v in ("#REF!", "#N/A", "#VALUE!", "#NAME?", "#DIV/0!"):
        return None
    if isinstance(v, datetime):
        return v.isoformat()
    return v


def normalize_col_name(raw, col_map, index):
    if raw is None:
        return f"column_{index}"
    s = str(raw).strip()
    if s in col_map:
        return col_map[s]
    if isinstance(raw, datetime):
        return f"date_{raw.strftime('%Y_%m_%d')}"
    s_clean = re.sub(r'[^\w]', '_', s.lower())
    s_clean = re.sub(r'_+', '_', s_clean).strip('_')
    if not s_clean or s_clean[0].isdigit():
        s_clean = f"col_{s_clean}"
    return s_clean if s_clean else f"column_{index}"


def td(args):
    """td コマンド実行（APIキー・エンドポイント固定）"""
    return subprocess.run(
        ["td", "-k", TD_API_KEY, "-e", TD_ENDPOINT] + args,
        capture_output=True, text=True
    )


def ensure_table(table_name):
    """テーブルが存在しない場合のみ REST API で作成"""
    r = subprocess.run(
        ["curl", "-s", "-H", f"Authorization: TD1 {TD_API_KEY}",
         f"{TD_ENDPOINT}/v3/table/show/{DATABASE}/{table_name}"],
        capture_output=True, text=True
    )
    if '"type"' in r.stdout:
        return  # 既存テーブルはそのまま使う
    # 作成（REST API 経由）
    subprocess.run(
        ["curl", "-s", "-X", "POST",
         "-H", f"Authorization: TD1 {TD_API_KEY}",
         f"{TD_ENDPOINT}/v3/table/create/{DATABASE}/{table_name}/log"],
        capture_output=True, text=True
    )


def upload_table(table_name, records):
    """td table:import --json でアップロード"""
    ensure_table(table_name)

    with tempfile.NamedTemporaryFile(
        mode='w', suffix='.json', delete=False, encoding='utf-8'
    ) as f:
        tmp_path = f.name
        for rec in records:
            rec_with_time = {"time": NOW_TS, **rec}
            f.write(json.dumps(rec_with_time, ensure_ascii=False) + "\n")

    try:
        r = td(["table:import", DATABASE, table_name,
                "--json", "-t", "time", tmp_path])
        if r.returncode != 0:
            raise RuntimeError(f"table:import failed: {r.stderr[:300]}")
        for line in r.stdout.splitlines():
            if "imported" in line or "skipped" in line or "Error" in line:
                print(f"    {line.strip()}")
    finally:
        os.unlink(tmp_path)


# ── メイン処理 ────────────────────────────────────────────────────────────────

wb = openpyxl.load_workbook(EXCEL_PATH, read_only=True, data_only=True)

for sheet_name, (table_name, header_row_idx) in SHEET_CONFIG.items():
    if sheet_name not in wb.sheetnames:
        print(f"  SKIP (not found): {sheet_name}")
        continue

    ws = wb[sheet_name]
    all_rows = list(ws.iter_rows(values_only=True))
    if not all_rows:
        print(f"  SKIP (empty): {sheet_name}")
        continue

    header_raw = all_rows[header_row_idx]
    data_rows = all_rows[header_row_idx + 1:]

    col_map = COLUMN_MAPS.get(table_name, {})
    header = [normalize_col_name(c, col_map, i) for i, c in enumerate(header_raw)]

    records = []
    for row in data_rows:
        if not any(v is not None for v in row):
            continue
        record = {header[i]: clean_value(v) for i, v in enumerate(row) if i < len(header)}
        record["excel_name"] = EXCEL_FILENAME
        record["excel_sheet_name"] = sheet_name
        records.append(record)

    if not records:
        print(f"  SKIP (no data rows): {sheet_name} → {table_name}")
        continue

    print(f"\nUploading: [{sheet_name}] → {table_name} ({len(records)} rows, {len(header)} cols)")
    try:
        upload_table(table_name, records)
        print(f"  ✓ Done: {table_name}")
    except Exception as e:
        print(f"  ✗ Error: {table_name}: {e}")

print("\nAll done.")
```

### 5-5. 完了後の件数確認

REST API でテーブルの件数を確認する（TD のインデックス構築に30秒〜数分かかる）:

```python
import time, subprocess, json

TD_API_KEY = "<account_id>/xxx..."
TD_ENDPOINT = "https://api.treasuredata.com"
DATABASE = "target_database"
tables = ["table_a", "table_b", ...]

time.sleep(30)  # 反映待ち

for tbl in tables:
    r = subprocess.run(
        ["curl", "-s", "-H", f"Authorization: TD1 {TD_API_KEY}",
         f"{TD_ENDPOINT}/v3/table/show/{DATABASE}/{tbl}"],
        capture_output=True, text=True
    )
    count = json.loads(r.stdout).get("count", 0)
    print(f"{tbl}: {count} rows")
```

---

## トラブルシューティング

### pytd が `key_default_database` エラーで失敗する

```
TypeError: <lambda>() got an unexpected keyword argument 'key_default_database'
```

**原因**: `pytd 2.2.0` + `tdclient 1.5.0` + `urllib3 v2` の組み合わせ非互換。  
**対処**: `pytd` は使わず `td table:import --json` に切り替える（本スキルの推奨手順）。

### td table:delete / table:create が失敗する

```
List databases failed: You don't have permission to list that database
```

**原因**: `td` コマンドがテーブル操作の前に `GET /v3/database/list` を呼んでいるが、APIキーにDB一覧権限がない。  
**対処**:
- テーブルの存在確認・作成は `curl` + REST API（`/v3/table/show/`, `/v3/table/create/`）で行う
- `table:import` 自体はこの権限チェックを行わないため、テーブルが存在すればそのまま使える

### td の接続先が別アカウント（JP など）になっている

```
~/.td/td.conf に別アカウントのAPIキーが設定されている
```

**対処**: 必ず `td -k <API_KEY> -e <ENDPOINT>` オプションで明示指定する。設定ファイルに依存しない。

### Bulk Import の perform 後に Valid Records: 0, Error Records: 全件

**原因**: msgpack フォーマットの不一致（`td bulk_import` の内部フォーマットと Python 側の生成方法が合わない）。  
**対処**: `td table:import --json` に切り替える。`time` カラムを必ず含めること（ないとスキップされる）。

### Bearer トークンで Bulk Import API が 404

```
{"error":"Path and method does not match any API endpoint"}
```

**原因**: Treasure Work の OAuth Bearer トークンは `/v3/bulk_import/*` に対応していない。  
**対処**: ユーザーに TD コンソールから Write 権限 API キーを取得してもらう。

---

## 注意事項

- **APIキーはスクリプトにハードコードしてよい**（ローカル実行・一時スクリプトの場合）。ただし Git にコミットしない。
- **数式セル**: `data_only=True` で計算済み値を取得するが、`#REF!` / `#N/A` 等のエラー値は `None` として扱う。
- **日付型カラムヘッダー**: 月次・日次データで1行目が `datetime` オブジェクトになることがある。`date_YYYY_MM_DD` 形式に変換する。
- **2行ヘッダー**: 1行目がタイトル・2行目がカラム名になっているシートは `header_row_idx=1` を指定する。
- **カラム名の漏れ**: COLUMN_MAPS に登録していない日本語カラム名は `normalize_col_name` で自動変換されるが、意図しない名前になることがある。事前に全カラムを登録しておくのが安全。
- **TD のデータ反映**: `table:import` 完了後、件数が REST API で確認できるまで30秒〜数分かかる。すぐに 0 rows が返っても正常。
