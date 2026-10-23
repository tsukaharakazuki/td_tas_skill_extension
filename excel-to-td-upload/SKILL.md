---
name: excel-to-td-upload
description: 'Use when the user wants to upload an Excel file (.xlsx) with one or more sheets to Treasure Data (TD), or to split an Excel file into per-sheet CSV files saved in a project folder for later upload. Two phases that can run separately: (1) Excel → CSV + manifest.json in a folder, with per-sheet confirmation, trailing-note cutoff after 20 consecutive blank rows, and Japanese → English table/column naming; (2) CSV → TD via the Bulk Import API (fast for large data, overwrite via temp table + swap, resumable). Standard-library Python only. Triggers on: ExcelをTDにアップロード, ExcelをTreasure Dataに取り込む, エクセルをインポート, シートごとにテーブルに, ExcelをCSVに分解, CSVをTDにアップロード, 大きいExcelの取り込みが遅い, Excel upload to TD, upload Excel to Treasure Data.'
---

# Excel → Treasure Data Upload

Excel をシートごとの CSV に分解してフォルダに保存し（フェーズA）、その CSV を Bulk Import API で TD に取り込む（フェーズB）。2つのフェーズは別々に実行できる。

**前提環境**: Treasure AI Studio（TAS）。Python 標準ライブラリだけで動く（`pip install`・`openpyxl`・`td` CLI は不要）。

| スクリプト | 役割 | TD への書き込み |
|---|---|---|
| `scripts/excel_to_csv.py` | Excel → `<テーブル名>.csv` + `manifest.json` | なし |
| `scripts/csv_to_td.py` | CSV + `manifest.json` → TD（Bulk Import API） | `--execute` を付けたときだけ |

## 守ること

- 質問は必ず `AskUserQuestion` を使う（各質問の options は2個以上）。テキストで質問しない。
- トークン・API キーの値を画面・ログ・ファイルに出さない。`echo` もしない。
- `csv_to_td.py --execute` は、計画表示（`--execute` なし）を見せてユーザーの了承を得てから実行する。
- overwrite は既存テーブルの中身を置き換える。対象テーブル名を示してから確認を取る。

---

## 準備: スクリプトの場所

このスキルのフォルダ（この SKILL.md と同じ場所）の `scripts/` を使う。パスが分からなければ探す:

```bash
SKILL_DIR=$(dirname "$(find / -name excel_to_csv.py -path '*excel-to-td-upload*' 2>/dev/null | head -1)")/..
ls "$SKILL_DIR/scripts"
```

---

# フェーズA: Excel → CSV（フォルダに保存）

## A1. Excel ファイルの特定

日本語ファイル名は `os.path.exists()` が誤判定することがあるため、`os.listdir()` で探す。

```bash
python3 -c "import os; base='.'; print([os.path.join(base, f) for f in os.listdir(base) if f.endswith('.xlsx')])"
```

複数あればユーザーに選んでもらう。

## A2. シートの下見（ファイルは書かない）

```bash
python3 "$SKILL_DIR/scripts/excel_to_csv.py" "<xlsx>" --inspect
```

シートごとに、非空行数・列数・先頭3行・**除外予定の末尾**が表示される。

**データ終端のルール**: 空行（空セル・空文字・空白だけの行）が **20行以上連続**したら、そこでデータを打ち切り、それ以降にある注記などのテキストは取り込まない。20行未満の空行は区切りとして扱い、取り込み時にスキップする。行数は config の `blank_run_limit` で変えられる。

結果を表にしてユーザーに見せる。空シート・目次シートはスキップ候補として示す。

## A3. ヒアリング（AskUserQuestion）

### 質問セット1: 取り込むシートとヘッダー

```
質問1: どのシートを取り込みますか？
  header: "シート選択"
  options:
    - label: "すべてのシート（推奨）"
      description: "空シート・目次シートは除外（下見で候補を提示済み）"
    - label: "一部のシートだけ"
      description: "Other で取り込むシート名（またはスキップするシート名）を入力"

質問2: ヘッダー行の構造はどれですか？
  header: "ヘッダー行"
  options:
    - label: "1行目がヘッダー（通常）"
      description: "header_row: 0"
    - label: "2行目がヘッダー（1行目はタイトル）"
      description: "header_row: 1"
    - label: "カテゴリ行＋項目行の2行を結合"
      description: "1行目がカテゴリ（カート落ち等）、2行目が項目名。列名は「カテゴリ_項目」"
```

シートごとに構造が違う場合は、下見結果から推定した案をシート別に示して確認する。

### 質問セット2: テーブル名・カラム名

TD の命名規則は **英小文字・数字・`_` のみ**。シート名と日本語のカラム名は Claude が英語に訳し、変換表を作って確認する（例: 申込日 → `application_date`、店舗名 → `store_name`、①売上データ → `sales_data`）。

```
質問3: テーブル名・カラム名の変換案で進めてよいですか？
  header: "変換確認"
  options:
    - label: "この変換で進める（推奨）"
      description: "（変換表を description に列挙）"
    - label: "修正する"
      description: "Other に「元の名前 → 新しい名前」の形式で入力"
```

## A4. config.json の作成

```json
{
  "blank_run_limit": 20,
  "sheets": {
    "売上データ": {"table": "sales_data", "header_row": 0},
    "店舗一覧":   {"table": "stores", "header_row": 1},
    "ファネル":   {"table": "funnel", "header_row": 1, "combine_category_row": true}
  },
  "column_maps": {
    "sales_data": {"申込日": "application_date", "店舗名": "store_name"},
    "funnel":     {"日付": "date", "カート落ち_件数": "cart_count", "購入_件数": "purchase_count"}
  }
}
```

- `header_row` は0始まり（0 = 1行目）。
- `combine_category_row: true` では、`header_row` の1行上がカテゴリ行になる。空のカテゴリは左の値を引き継ぐ。`column_maps` のキーは `カテゴリ_項目` の形にする。
- `sheets` に書いたシートだけを取り込む。

## A5. 変換の実行（フォルダに保存）

出力先は、プロジェクトフォルダ内の `excel_to_td/<Excelファイル名（拡張子なし）>/` にする。

```bash
python3 "$SKILL_DIR/scripts/excel_to_csv.py" "<xlsx>" "excel_to_td/<name>" --config config.json
```

出力:
- `<テーブル名>.csv`（UTF-8・ヘッダー付き）。各行の末尾に固定カラム `excel_name`（ファイル名）と `excel_sheet_name`（元のシート名）が付く。
- `manifest.json`（シート ↔ テーブル、データ範囲、行数、カラム名と型、打ち切り情報、警告）。

## A6. シートごとの確認（必須）

スクリプトの出力を、シートごとに次の形でユーザーに見せる:

| シート | テーブル | ヘッダー | データ範囲 | 件数 | 末尾の除外 |
|---|---|---|---|---|---|
| 売上データ | sales_data | 1行目 | 2〜1,204行 | 1,180 | 1,205行目以降（先頭「※ 注記…」） |

- 警告（`!` で始まる行）があれば必ず伝える。例: `column_N`（英数字にできなかったカラム）、`*_src`（予約カラム名との重複による改名）。`column_N` が残っている場合は `column_maps` を直して A5 をやり直す。
- 除外された先頭テキストがデータの一部なら、`blank_run_limit` を上げて A5 をやり直す。

確認が済めばフェーズAは完了。CSV はフォルダに残るので、フェーズBは後から別に実行してもよい。

---

# フェーズB: CSV → TD（Bulk Import API）

## B1. 認証

TAS では `mcp__tas__request_credential` でトークンを受け取り、環境変数に入れる（値は表示しない）。

```python
import os
os.environ["TDX_ACCESS_TOKEN"] = "<mcp__tas__request_credential で取得した値>"   # 例: credential_name="td_api_production_aws"
os.environ["TDX_SITE"] = "us01"   # JP: jp01 / EU: eu01 / AP: ap02
```

`csv_to_td.py` は次の順で認証情報と接続先を決める:

| 用途 | 優先順 |
|---|---|
| 認証 | `TD_API_KEY` → `TDX_ACCESS_TOKEN` |
| 接続先 | `TD_ENDPOINT` → `TDX_SITE` |
| 方式 | `TD_AUTH_SCHEME` → 自動判定（`ACCOUNT_ID/KEY` 形式なら `TD1`、それ以外は `Bearer`） |

## B2. 接続確認（書き込みなし）

```bash
python3 "$SKILL_DIR/scripts/csv_to_td.py" "excel_to_td/<name>" --database <db> --check
```

- **すべて OK** → B3 へ。
- **Bulk Import API が NG（401/403）** → OAuth トークンでは Bulk Import を使えない。書き込み権限のある API キーを `TD_API_KEY` に設定してもらい、もう一度 `--check` する。
- **データベース参照が NG（404）** → DB 名を確認する。DB の新規作成はこのスキルでは行わない。

`--check` が通っても、データ送信（upload_part）の権限までは確かめられない。初回は小さいシートで試す（`--tables <1テーブル>`）。

## B3. 取り込み方法の確認と計画表示

```
質問: 既存テーブルがある場合の扱いは？
  header: "既存データ"
  options:
    - label: "上書き（overwrite）（推奨）"
      description: "一時テーブルに取り込んでから入れ替える。失敗しても既存テーブルは変わらない"
    - label: "追記（append）"
      description: "既存テーブルに行を足す。テーブルがなければ作成する"
```

```bash
python3 "$SKILL_DIR/scripts/csv_to_td.py" "excel_to_td/<name>" --database <db> --mode overwrite
```

`--execute` を付けない実行は計画の表示だけ（TD には書き込まない）。テーブル・行数・パート数・カラムと型を見せ、了承を得る。

## B4. 取り込みの実行

データが大きいとツールの実行時間を超えることがあるため、バックグラウンドで実行し、ログを確認する。

```bash
cd "excel_to_td/<name>"
nohup python3 "$SKILL_DIR/scripts/csv_to_td.py" . --database <db> --mode overwrite --execute > upload.log 2>&1 &
tail -n 20 upload.log
```

処理の流れ（テーブルごと）:
1. overwrite: 一時テーブル `<table>_tmp_<unixtime>` を型付きで作る。append: 本テーブルがなければ作る。
2. Bulk Import セッションを作り、CSV を `--part-rows`（既定10万行）ずつ msgpack.gz で送る。
3. freeze → perform → `ready` まで待つ → エラーレコードが0件なら commit。
4. overwrite: 本テーブルと一時テーブルを swap し、旧データ（一時テーブル側）を削除する。
5. 成否を `upload_progress_<db>.json` に記録する。もう一度実行すると、完了済みのテーブルは飛ばす。

エラーレコードが1件でもあれば commit せずに止める（既存テーブルは変わらない）。許容する場合だけ `--allow-errors` を付ける。

## B5. 件数の確認

```bash
tdx query "SELECT COUNT(*) AS cnt FROM <db>.<table>"
```

`manifest.json` の `data_rows` と一致するか、テーブルごとに報告する。

---

## 取り込み後のテーブル

| カラム | 型 | 内容 |
|---|---|---|
| `time` | long | 取り込んだ時刻（UNIX 秒）。TD の予約カラム |
| （Excel の列） | long / double / string | 列全体が整数なら long、小数を含めば double、それ以外は string |
| `excel_name` | string | Excel ファイル名 |
| `excel_sheet_name` | string | 元のシート名（翻訳前） |

- 日付・日時セルは ISO 形式の文字列（`2026-10-01T00:00:00`）になる。
- `#REF!`・`#N/A` などのエラー値と空セルは NULL になる。
- Excel 側に `time`・`excel_name`・`excel_sheet_name` という列があると、`*_src` に改名される。

---

## トラブルシューティング

| 症状 | 原因と対処 |
|---|---|
| `--check` で Bulk Import API が 401/403 | OAuth トークンは Bulk Import に使えない。書き込み権限のある API キーを `TD_API_KEY` に設定する |
| 取り込み結果でエラーレコードが出る | `manifest.json` の型と実際の値が合っていない可能性がある。CSV を確認する。許容するなら `--allow-errors` |
| 途中で止まった（タイムアウト・通信断） | 同じコマンドをもう一度実行する。完了済みのテーブルは飛ばす。テーブルをやり直す場合は `upload_progress_<db>.json` から該当テーブルを消す |
| `<table>_tmp_<数字>` が残っている | 強制終了などで後始末が走らなかった。中身を確認してから `tdx` 等で削除する |
| カラム名が `column_N` になる | 日本語だけのヘッダーは英数字にできない。`column_maps` で英語名を指定して A5 をやり直す |
| 注記行がデータに混ざる | 注記の手前の空行が20行未満。`blank_run_limit` を下げるか、Excel 側で空行を入れる |
| 必要な行まで除外される | データの途中に20行以上の空行がある。`blank_run_limit` を上げる |
| `FileNotFoundError`（日本語ファイル名） | `os.listdir()` で見つけたパスをそのまま渡す |

## テスト

```bash
cd "$SKILL_DIR" && python3 -m unittest discover -s tests -v
```

TD には接続しない（模擬サーバーで Bulk Import の流れを確かめる）。
