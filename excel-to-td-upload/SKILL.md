---
name: excel-to-td-upload
description: 'Use when the user wants to upload an Excel file (.xlsx) with multiple sheets to Treasure Data (TD). Triggers on: ExcelをTDにアップロード, ExcelをTreasure Dataに取り込む, スプレッドシートをTDに, エクセルをインポート, シートごとにテーブルに, Excel upload to TD, upload Excel to Treasure Data, or any request to import a multi-sheet Excel file into a TD database/table.'
---

# Excel → Treasure Data Upload

ExcelファイルをTreasure Dataにアップロードする対話型ウィザード。シートごとのテーブル分割、日本語→英語変換、カラム名正規化を自動で行う。

**前提環境**: Treasure AI Studio（TAS）。`tdx` CLI と OAuth Bearer Token を使用する。`td` CLI・`pip install`・外部PyPIは利用不可。

---

## Step 0: TDX 認証チェック

最初に `tdx` が正常に動作するか確認する。失敗した場合はトークンを取得してから進む。

```bash
tdx databases
```

失敗（401 / 認証エラー）した場合:

```python
# mcp__tas__request_credential でトークンを取得
# credential_name は "td_api_production_aws" など環境に合わせて指定
import os, subprocess
token = "<mcp__tas__request_credential で取得したトークン>"
os.environ["TDX_ACCESS_TOKEN"] = token
os.environ["TDX_SITE"] = "us01"  # JP環境なら "jp01"

# 再確認
subprocess.run(["tdx", "databases"], capture_output=True, text=True)
```

---

## Step 1: Excelファイルの調査

### ファイルパスの特定（日本語ファイル名対応）

日本語ファイル名は `os.path.exists()` が誤検出するケースがある。`os.listdir()` で探す。

```python
import os

base = '/home/agent/projects/project-1782743340050/'  # ファイルが置かれているディレクトリ
xlsx_files = [os.path.join(base, f) for f in os.listdir(base) if f.endswith('.xlsx')]
print(xlsx_files)
# → ユーザーに提示して選ばせる、または名前にキーワードが含まれるものを自動選択
```

### XLSXパース（標準ライブラリのみ・openpyxl不要）

TAS環境は外部PyPIに出られないため `openpyxl` は使えない。`zipfile` + `xml.etree` で読む。
日本語ファイル名対応のため `open(rb)` → `io.BytesIO` 経由で開く。

```python
import zipfile, io, xml.etree.ElementTree as ET, re
from datetime import datetime, timedelta

def col_letter_to_index(col_str):
    idx = 0
    for c in col_str.upper():
        idx = idx * 26 + (ord(c) - ord('A') + 1)
    return idx - 1

def parse_cell_ref(ref):
    m = re.match(r'([A-Z]+)(\d+)', ref)
    return col_letter_to_index(m.group(1)), int(m.group(2)) - 1

def excel_serial_to_datetime(serial):
    base = datetime(1899, 12, 30) if serial >= 60 else datetime(1899, 12, 31)
    return (base + timedelta(days=float(serial))).isoformat()

def parse_xlsx(path):
    ns = {'w': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
    # 日本語ファイル名対応: バイト列で読んでから BytesIO に渡す
    with open(path, 'rb') as fh:
        data = fh.read()
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        shared = []
        if 'xl/sharedStrings.xml' in z.namelist():
            root = ET.fromstring(z.read('xl/sharedStrings.xml'))
            for si in root.findall('w:si', ns):
                texts = [t.text or '' for t in si.iter('{http://schemas.openxmlformats.org/spreadsheetml/2006/main}t')]
                shared.append(''.join(texts))
        wb_root = ET.fromstring(z.read('xl/workbook.xml'))
        sheets = [(s.get('name'), s.get('{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id'))
                  for s in wb_root.findall('.//w:sheet', ns)]
        rels = ET.fromstring(z.read('xl/_rels/workbook.xml.rels'))
        rel_map = {r.get('Id'): r.get('Target') for r in rels}
        result = {}
        for sheet_name, rid in sheets:
            target = rel_map.get(rid, '')
            fpath = f'xl/{target}' if not target.startswith('xl/') else target
            if fpath not in z.namelist():
                continue
            ws_root = ET.fromstring(z.read(fpath))
            rows_data = {}
            for row_el in ws_root.findall('.//w:row', ns):
                for c_el in row_el.findall('w:c', ns):
                    ref = c_el.get('r', '')
                    t = c_el.get('t', '')
                    v_el = c_el.find('w:v', ns)
                    if v_el is None or v_el.text is None:
                        val = None
                    elif t == 's':
                        val = shared[int(v_el.text)]
                    elif t == 'b':
                        val = bool(int(v_el.text))
                    else:
                        raw = v_el.text
                        try:
                            val = int(raw) if '.' not in raw else float(raw)
                        except (ValueError, TypeError):
                            val = raw
                        style_idx = int(c_el.get('s', -1))
                        if isinstance(val, (int, float)) and style_idx in (14, 15, 16, 17, 22):
                            val = excel_serial_to_datetime(val)
                    col_idx, row_idx = parse_cell_ref(ref)
                    rows_data.setdefault(row_idx, {})[col_idx] = val
            if not rows_data:
                continue
            max_row = max(rows_data.keys())
            max_col = max(max(row.keys()) for row in rows_data.values())
            grid = [[rows_data.get(r, {}).get(c) for c in range(max_col + 1)]
                    for r in range(max_row + 1)]
            result[sheet_name] = grid
    return result

sheets = parse_xlsx("path/to/file.xlsx")
for sheet_name, rows in sheets.items():
    non_empty = [r for r in rows if any(v is not None for v in r)]
    print(f"[{sheet_name}] 総行数: {len(rows)}, 非空行数: {len(non_empty)}, カラム数: {len(rows[0]) if rows else 0}")
    if rows:
        print(f"  1行目: {rows[0][:6]}")
```

調査結果をユーザーに提示し、空シート・目次シートをスキップ候補として提案する。

---

## Step 2: ヒアリング（AskUserQuestion を使う）

**必ず `AskUserQuestion` ツールを使う。テキスト文章で質問してはいけない。各質問の options は必ず2個以上。**

### 質問セット A（1回目）: DB名・シート選択

```
質問1: アップロード先のDatabase名は何ですか？
  header: "Database名"
  options:
    - label: "既存のDBに追加（推奨）"
      description: "既存データベース名を Other で入力してください（例: my_database）"
    - label: "新規DBを作成"
      description: "新しいデータベース名を Other で入力してください（例: my_new_database）"

質問2: どのシートを取り込みますか？
  header: "シート選択"
  options:
    - label: "すべてのシート（推奨）"
      description: "空・目次シートは自動スキップ候補として提示済み"
    - label: "一部のシートだけ（Other で列挙）"
      description: "取り込みたいシート名、またはスキップしたいシート名を入力"
```

### 質問セット B（2回目）: ヘッダー構造・既存データ

```
質問3: ヘッダー行の構造はどれですか？
  header: "ヘッダー行"
  options:
    - label: "1行目がヘッダー（通常構造）"
      description: "1行目がカラム名のシートに適用"
    - label: "2行目がヘッダー（1行目はタイトル行）"
      description: "1行目がタイトル行、2行目がカラム名のシートに適用"
    - label: "カテゴリ行 + 項目行の2行を結合する"
      description: "1行目がカテゴリ（カート落ち等）、2行目が項目名のシートに適用"

質問4: 既存テーブルがある場合の扱いは？
  header: "既存データ"
  options:
    - label: "上書き（overwrite）（推奨）"
      description: "既存データを全て削除して新しいデータで置き換える"
    - label: "追記（append）"
      description: "既存データの末尾に追加する"
```

### 質問セット C（3回目）: テーブル名・カラム名変換確認

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

```python
import re
from datetime import datetime

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
```

変換例: 申込日→`application_date` / 店舗名→`store_name` / ①売上データ→`sales_data` / ★評価→`star_rating`

### 2行ヘッダー結合（カテゴリ×項目パターン）

1行目がカテゴリ（カート落ち・購入等）、2行目が項目名のマトリクス構造の場合:

```python
def build_combined_header(cat_row, item_row, cat_map, item_map):
    """カテゴリ行 × 項目行 を結合してカラム名を生成（Noneは直前の値を継承）"""
    last_cat = None
    result = []
    for cat, item in zip(cat_row, item_row):
        if cat is not None:
            last_cat = cat
        if item in item_map and last_cat is None:
            result.append(item_map[item])
        else:
            cat_en = cat_map.get(last_cat, normalize_col_name(last_cat, {}, 0)) if last_cat else ''
            item_en = item_map.get(item, normalize_col_name(item, {}, 0)) if item else 'col'
            result.append(f"{cat_en}_{item_en}" if cat_en else item_en)
    return result

# 使い方（SHEET_CONFIG でヘッダー行を2行分指定）
# cat_row  = all_rows[0]  # カテゴリ行
# item_row = all_rows[1]  # 項目行
# header = build_combined_header(cat_row, item_row, cat_map={}, item_map={})
```

Claude自身が日本語カラム名を英語に翻訳し、変換案をユーザーに提示して確認を取る。

---

## Step 4: 固定カラムの付与

すべてのテーブルに以下の2カラムを自動付与する:

| カラム名 | 値 |
|---------|-----|
| `excel_name` | アップロードしたExcelファイル名（拡張子含む） |
| `excel_sheet_name` | 元のシート名（翻訳前の原文） |

---

## Step 5: アップロード（tdx query 経由）

`tdx query` + Trino INSERT INTO でデータを投入する。

### 重要制約

- SQLは必ず `-f <ファイルパス>` で渡す（argv上限超過を防ぐため。直接渡すと `OSError: Argument list too long`）
- **全行に `CAST` で型を明示する**（行ごとに型が変わると Trino が型解決できず `TYPE_MISMATCH` になる）
- バッチサイズは500行が安定（1バッチ約15〜20秒）
- 文字列中の `'` は `''` にエスケープする

### アップロードスクリプト

```python
import os, re, json, subprocess, tempfile
from datetime import datetime

EXCEL_PATH    = "path/to/file.xlsx"
DATABASE      = "target_database"
BATCH_SIZE    = 500
EXCEL_FILENAME = os.path.basename(EXCEL_PATH)
PROGRESS_FILE  = f"/tmp/upload_progress_{DATABASE}.json"

# シート名 → (テーブル名, ヘッダー行インデックス 0始まり)
SHEET_CONFIG = {
    "シートA": ("table_a", 0),
    "シートB": ("table_b", 1),  # 2行目がヘッダーの場合
}
# カラム名変換マップ（シートごと。未登録は normalize_col_name で自動変換）
COLUMN_MAPS = {
    "table_a": {"日本語カラム名": "english_col"},
}


def normalize_col_name(raw, col_map, index):
    if raw is None: return f"column_{index}"
    s = str(raw).strip()
    if s in col_map: return col_map[s]
    s_clean = re.sub(r'[^\w]', '_', s.lower())
    s_clean = re.sub(r'_+', '_', s_clean).strip('_')
    if not s_clean or s_clean[0].isdigit(): s_clean = f"col_{s_clean}"
    return s_clean if s_clean else f"column_{index}"

def clean_value(v):
    if v is None: return None
    import math
    if isinstance(v, float) and (math.isnan(v) or math.isinf(v)): return None
    if isinstance(v, str) and v in ("#REF!", "#N/A", "#VALUE!", "#NAME?", "#DIV/0!"): return None
    if isinstance(v, datetime): return v.isoformat()
    return v

def infer_col_types(records, header):
    """全レコードを走査して各カラムの Trino 型を決定する"""
    col_types = {}
    for col in header:
        for rec in records:
            v = rec.get(col)
            if v is None:
                continue
            if isinstance(v, bool):
                col_types[col] = 'VARCHAR'; break
            if isinstance(v, int):
                col_types.setdefault(col, 'BIGINT')
            elif isinstance(v, float):
                col_types[col] = 'DOUBLE'
            else:
                col_types[col] = 'VARCHAR'; break
        col_types.setdefault(col, 'VARCHAR')
    return col_types

def to_sql_literal_typed(v, col_type):
    """全行に CAST を付けて型を明示する（TYPE_MISMATCH 防止）"""
    if v is None:
        return f"CAST(NULL AS {col_type})"
    if col_type == 'BIGINT':
        return f"CAST({int(v)} AS BIGINT)"
    if col_type == 'DOUBLE':
        return f"CAST({float(v)} AS DOUBLE)"
    return f"CAST('{str(v).replace(chr(39), chr(39)*2)}' AS VARCHAR)"

def tdx_query(sql):
    """SQLをファイル経由で tdx query に渡す（argv上限回避）"""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.sql', delete=False, encoding='utf-8') as f:
        f.write(sql)
        tmp = f.name
    try:
        r = subprocess.run(
            ["tdx", "query", "-d", DATABASE, "-f", tmp],
            capture_output=True, text=True
        )
        return r
    finally:
        os.unlink(tmp)

def upload_table(table_name, header, records, mode="overwrite"):
    col_list = ", ".join(header)
    col_types = infer_col_types(records, header)

    if mode == "overwrite":
        tdx_query(f"DROP TABLE IF EXISTS {DATABASE}.{table_name}")
        print(f"  DROP {table_name}")
        table_exists = False  # DROP済みなので SHOW TABLES は不要
    else:
        r = tdx_query(f"SHOW TABLES LIKE '{table_name}'")
        table_exists = table_name in r.stdout

    total = len(records)
    for batch_start in range(0, total, BATCH_SIZE):
        batch = records[batch_start:batch_start + BATCH_SIZE]
        rows_sql = []
        for rec in batch:
            vals = ", ".join(to_sql_literal_typed(rec.get(col), col_types[col]) for col in header)
            rows_sql.append(f"  ({vals})")
        values_clause = ",\n".join(rows_sql)

        if not table_exists and batch_start == 0:
            sql = f"CREATE TABLE {DATABASE}.{table_name} AS\nSELECT * FROM (VALUES\n{values_clause}\n) AS t({col_list})"
            table_exists = True
        else:
            sql = f"INSERT INTO {DATABASE}.{table_name} ({col_list})\nSELECT * FROM (VALUES\n{values_clause}\n) AS t({col_list})"

        r = tdx_query(sql)
        if r.returncode != 0:
            raise RuntimeError(f"Query failed:\n{r.stderr[:500]}")

        print(f"  [{table_name}] {min(batch_start + BATCH_SIZE, total)}/{total} rows")

    progress = {}
    if os.path.exists(PROGRESS_FILE):
        with open(PROGRESS_FILE) as f:
            progress = json.load(f)
    progress[table_name] = {"rows": total, "done": True}
    with open(PROGRESS_FILE, "w") as f:
        json.dump(progress, f)


# ── メイン処理 ──────────────────────────────────────────────
# sheets は Step 1 の parse_xlsx() で取得した dict
# sheets = { "シート名": [[row0col0, ...], [row1col0, ...], ...] }

progress = {}
if os.path.exists(PROGRESS_FILE):
    with open(PROGRESS_FILE) as f:
        progress = json.load(f)
    print(f"Resume: {list(progress.keys())}")

for sheet_name, (table_name, header_row_idx) in SHEET_CONFIG.items():
    if progress.get(table_name, {}).get("done"):
        print(f"SKIP (already done): {table_name}")
        continue
    if sheet_name not in sheets:
        print(f"SKIP (not found): {sheet_name}")
        continue

    all_rows = sheets[sheet_name]
    if not all_rows:
        print(f"SKIP (empty): {sheet_name}")
        continue

    col_map = COLUMN_MAPS.get(table_name, {})
    header_raw = all_rows[header_row_idx]
    header = [normalize_col_name(c, col_map, i) for i, c in enumerate(header_raw)]
    header += ["excel_name", "excel_sheet_name"]

    records = []
    for row in all_rows[header_row_idx + 1:]:
        if not any(v is not None for v in row):
            continue
        rec = {header[i]: clean_value(v) for i, v in enumerate(row) if i < len(header) - 2}
        rec["excel_name"] = EXCEL_FILENAME
        rec["excel_sheet_name"] = sheet_name
        records.append(rec)

    if not records:
        print(f"SKIP (no data): {sheet_name}")
        continue

    print(f"\nUploading [{sheet_name}] → {table_name} ({len(records)} rows)")
    try:
        upload_table(table_name, header, records, mode="overwrite")
        print(f"  Done: {table_name}")
    except Exception as e:
        print(f"  ERROR: {table_name}: {e}")

print("\nAll done.")
```

---

## トラブルシューティング

### `OSError: [Errno 7] Argument list too long`
**原因**: VALUES句が大きく argv 上限を超えた。  
**対処**: `tdx query -f <path>` でSQLをファイル経由で渡す（本スキルの標準手順）。

### `[TYPE_MISMATCH] Table: [bigint], Query: [integer]`
**原因**: 行ごとに型が変わり Trino が型を解決できない。  
**対処**: `infer_col_types` で全カラムの型を事前決定し、全行に `CAST` を付ける（本スキルの標準手順）。

### `FileNotFoundError` でファイルが開けない
**原因**: 日本語ファイル名で `os.path.exists()` が誤検出するケースがある。  
**対処**: `os.listdir()` でファイルを探し、`open(path, 'rb')` → `io.BytesIO` 経由で開く（本スキルの標準手順）。

### Bearer Token で書き込みAPIが失敗する
**原因**: TAS の OAuth Bearer Token は Bulk Import API（`/v3/bulk_import/*`）に非対応。  
**対処**: `tdx query` 経由 INSERT INTO を使う（本スキルの標準手順）。

### `tdx` が 401 エラーで失敗する
**原因**: TDX 認証トークンが未設定または期限切れ。  
**対処**: Step 0 の手順で `mcp__tas__request_credential` を呼んでトークンを再取得する。

---

## 注意事項

- **バッチサイズ**: 500行/バッチが安定（1バッチ約15〜20秒）。`-f` ファイル経由なら1000行も試す価値あり。
- **進捗ファイル**: `/tmp/upload_progress_<db>.json` に完了シートを記録。中断後は自動スキップ（レジューム対応）。
- **末尾ノート行の処理**: シート末尾に補足説明が含まれる場合、データ終端行を `SHEET_CONFIG` で手動指定するか、「1列目が None かつ特定行以降はすべて None」パターンで自動検出する。
- **2行ヘッダー**: 1行目がタイトル・2行目がカラム名のシートは `header_row_idx=1` を指定。カテゴリ×項目の2行マトリクスは `build_combined_header` を使う。
- **数式セル**: `#REF!` 等のエラー値は `None` として扱う。
