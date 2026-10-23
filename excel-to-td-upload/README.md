# excel-to-td-upload

Treasure AI Studio（TAS）用のスキル。Excel（.xlsx）をシートごとの CSV に分解してフォルダに保存し、Bulk Import API で Treasure Data に取り込む。

## 概要

- **2フェーズに分離**: 「Excel → CSV（フォルダに保存）」と「CSV → TD」を別々に実行できる。大きなデータでも、分解したCSVを確認してから取り込める。
- **Bulk Import API で高速に取り込み**: 以前の `tdx query` による INSERT（500行ずつ）をやめた。
- **シートごとの確認**: データ範囲・件数・除外した末尾をシートごとに表示する。空行が20行以上続いたら、そこでデータを打ち切る（末尾の注記を取り込まない）。
- **安全な上書き**: 一時テーブルに取り込んでから swap する。失敗しても既存テーブルは変わらない。
- **再開できる**: テーブルごとの完了状況を記録し、再実行時には完了済みのテーブルを飛ばす。
- **日本語 → 英語の命名**: テーブル名・カラム名を TD の命名規則（英小文字・数字・`_`）に合わせる。
- **標準ライブラリだけで動く**: `pip install`・`openpyxl`・`td` CLI は不要。

## 構成

```
excel-to-td-upload/
├── SKILL.md                 # 手順（TAS の Claude が読む）
├── scripts/
│   ├── excel_to_csv.py      # Excel → CSV + manifest.json（TD に接続しない）
│   └── csv_to_td.py         # CSV + manifest.json → TD（Bulk Import API）
└── tests/
    └── test_excel_to_td.py  # 単体テスト（模擬サーバーを使い、TD に接続しない）
```

## インストール

```bash
# TAS / Treasure Work のスキルフォルダにフォルダごとコピー
cp -r excel-to-td-upload ~/.treasure-work/.claude/skills/
```

## 使い方

チャットで `/excel-to-td-upload` と入力するか、Excel を添付して「この Excel を TD にアップロードしたい」と依頼する。

スクリプトを直接使う場合:

```bash
# A. 分解
python3 scripts/excel_to_csv.py book.xlsx --inspect                          # 下見（ファイルは書かない）
python3 scripts/excel_to_csv.py book.xlsx excel_to_td/book --config config.json

# B. 取り込み
python3 scripts/csv_to_td.py excel_to_td/book --database my_db --check       # 認証と Bulk Import API の確認（書き込みなし）
python3 scripts/csv_to_td.py excel_to_td/book --database my_db               # 計画の表示（書き込みなし）
python3 scripts/csv_to_td.py excel_to_td/book --database my_db --execute     # 取り込み
```

## 認証

| 環境変数 | 内容 |
|---|---|
| `TD_API_KEY` | 書き込み権限のある API キー（`ACCOUNT_ID/KEY`）。なければ `TDX_ACCESS_TOKEN` を使う |
| `TDX_ACCESS_TOKEN` | TAS の `mcp__tas__request_credential` で受け取ったトークン |
| `TD_ENDPOINT` / `TDX_SITE` | 接続先。`TDX_SITE` は `us01` / `jp01` / `eu01` / `ap02` |

OAuth トークンで Bulk Import API が使えない環境では、`--check` が NG を返す。その場合は `TD_API_KEY` に API キーを設定する。

## テスト

```bash
python3 -m unittest discover -s tests -v
```

## 注意事項

- 実際の TD での動作確認は、利用する環境で `--check` と小さいシートでの試験取り込みによって行うこと。
- `time` 列には取り込み時刻が入る（TD の予約カラム）。
- 日付セルは ISO 形式の文字列で取り込む。

## ライセンス

MIT
