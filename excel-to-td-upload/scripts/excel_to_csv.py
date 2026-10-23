#!/usr/bin/env python3
"""
Excel(.xlsx) → CSV + manifest.json（標準ライブラリのみ・openpyxl 不要）

使い方:
  python3 excel_to_csv.py <xlsx> --inspect                    # シートの下見のみ（ファイルは書かない）
  python3 excel_to_csv.py <xlsx> <out_dir> [--config config.json]

config.json（任意。省略時は全シートを取り込み、テーブル名はシート名から自動生成）:
  {
    "blank_run_limit": 20,
    "sheets": {"シートA": {"table": "table_a", "header_row": 0}},
    "column_maps": {"table_a": {"日本語カラム名": "english_col"}}
  }
  header_row は 0 始まり（0 = 1行目がヘッダー）
  "combine_category_row": true を付けると、header_row の1行上をカテゴリ行として
  「カテゴリ_項目」で列名を作る（空のカテゴリは左の値を引き継ぐ）。column_maps のキーも「カテゴリ_項目」
"""
import argparse
import csv
import json
import math
import os
import re
import zipfile
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta

NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
REL = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"
PKG_REL = "{http://schemas.openxmlformats.org/package/2006/relationships}"

DEFAULT_BLANK_RUN_LIMIT = 20
EXCEL_EPOCH = datetime(1899, 12, 30)
BUILTIN_DATE_FORMAT_IDS = set(range(14, 23)) | {45, 46, 47}
EXCEL_ERRORS = {"#REF!", "#N/A", "#VALUE!", "#NAME?", "#DIV/0!", "#NUM!", "#NULL!"}
FIXED_COLUMNS = ["excel_name", "excel_sheet_name"]
RESERVED_COLUMNS = set(FIXED_COLUMNS) | {"time"}  # time は TD の予約カラム（取り込み時に付与）


# ── xlsx 読み込み ─────────────────────────────────────────────────────────────

def col_index(letters):
    """'A' → 0, 'AA' → 26"""
    n = 0
    for ch in letters:
        n = n * 26 + (ord(ch) - ord("A") + 1)
    return n - 1


def is_date_format(code):
    # 引用符・角括弧・エスケープの中身は書式記号ではないので除く
    stripped = re.sub(r'"[^"]*"|\[[^\]]*\]|\\.', "", code)
    return re.search(r"[ymdhs]", stripped, re.IGNORECASE) is not None


def load_date_style_ids(z):
    """日付・時刻の書式を持つ cellXfs のインデックス集合"""
    if "xl/styles.xml" not in z.namelist():
        return set()
    root = ET.fromstring(z.read("xl/styles.xml"))
    custom = {int(n.get("numFmtId")): n.get("formatCode", "") for n in root.iter(NS + "numFmt")}
    xfs = root.find(NS + "cellXfs")
    if xfs is None:
        return set()
    ids = set()
    for i, xf in enumerate(xfs.findall(NS + "xf")):
        fmt = int(xf.get("numFmtId", 0))
        if fmt in BUILTIN_DATE_FORMAT_IDS or (fmt in custom and is_date_format(custom[fmt])):
            ids.add(i)
    return ids


def shared_text(si):
    """共有文字列 1件のテキスト（ふりがな rPh は除外）"""
    parts = []
    for node in si:
        if node.tag == NS + "t":
            parts.append(node.text or "")
        elif node.tag == NS + "r":
            parts.extend(t.text or "" for t in node.findall(NS + "t"))
    return "".join(parts)


def load_shared_strings(z):
    if "xl/sharedStrings.xml" not in z.namelist():
        return []
    root = ET.fromstring(z.read("xl/sharedStrings.xml"))
    return [shared_text(si) for si in root.findall(NS + "si")]


def list_sheets(z):
    """(シート名, シートXMLのパス) の一覧（ブック内の順）"""
    wb = ET.fromstring(z.read("xl/workbook.xml"))
    rels = ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))
    targets = {r.get("Id"): r.get("Target") for r in rels.iter(PKG_REL + "Relationship")}
    out = []
    for s in wb.iter(NS + "sheet"):
        target = targets.get(s.get(REL + "id"), "")
        path = target.lstrip("/") if target.startswith("/") else "xl/" + target
        out.append((s.get("name"), path))
    return out


def excel_serial_to_value(serial):
    if serial < 1:  # 時刻だけのセル
        secs = round(serial * 86400)
        return f"{secs // 3600:02d}:{secs % 3600 // 60:02d}:{secs % 60:02d}"
    return EXCEL_EPOCH + timedelta(days=serial)


def read_cell(c, shared, date_style_ids):
    t = c.get("t", "n")
    if t == "inlineStr":
        return "".join(x.text or "" for x in c.iter(NS + "t"))
    v_el = c.find(NS + "v")
    if v_el is None or v_el.text is None:
        return None  # 書式だけ付いた空セル
    raw = v_el.text
    if t == "s":
        return shared[int(raw)]  # 空文字の共有文字列はここで "" になる
    if t == "b":
        return raw == "1"
    if t in ("str", "e"):
        return raw
    num = float(raw)
    if int(c.get("s", 0)) in date_style_ids:
        return excel_serial_to_value(num)
    return int(num) if num.is_integer() else num


def read_sheet_grid(z, path, shared, date_style_ids):
    """シートを二次元リストにする。行列の欠け（空セル・空行）は None で埋める"""
    root = ET.fromstring(z.read(path))
    grid = {}
    next_row = 0
    for row_el in root.iter(NS + "row"):
        r_idx = int(row_el.get("r")) - 1 if row_el.get("r") else next_row
        next_row = r_idx + 1
        cells = grid.setdefault(r_idx, {})
        next_col = 0
        for c in row_el.findall(NS + "c"):
            ref = c.get("r")
            col = col_index(re.match(r"[A-Z]+", ref).group()) if ref else next_col
            cells[col] = read_cell(c, shared, date_style_ids)
            next_col = col + 1
    if not grid:
        return []
    width = max((max(cells) for cells in grid.values() if cells), default=-1) + 1
    return [[grid.get(r, {}).get(c) for c in range(width)] for r in range(max(grid) + 1)]


# ── 値の判定・変換 ───────────────────────────────────────────────────────────

def normalize_value(v):
    """Excel のエラー値・NaN は None にする"""
    if isinstance(v, str) and v in EXCEL_ERRORS:
        return None
    if isinstance(v, float) and (math.isnan(v) or math.isinf(v)):
        return None
    return v


def is_blank(v):
    """None・空文字・空白のみ・エラー値は空とみなす"""
    v = normalize_value(v)
    return v is None or (isinstance(v, str) and not v.strip())


def is_blank_row(row):
    return all(is_blank(v) for v in row)


def first_text(row):
    for v in row:
        if not is_blank(v):
            return str(normalize_value(v))
    return ""


def csv_text(v):
    if v is None:
        return ""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, datetime):
        return v.isoformat()
    return str(v)


def infer_type(values):
    """カラム全体から TD の型を決める（BIGINT / DOUBLE / VARCHAR）"""
    kinds = set()
    for v in values:
        if v is None or v == "":
            continue
        if isinstance(v, bool) or not isinstance(v, (int, float)):
            return "VARCHAR"
        kinds.add("int" if isinstance(v, int) else "float")
    if not kinds:
        return "VARCHAR"
    if kinds == {"int"}:
        return "BIGINT"
    return "DOUBLE"


# ── 名前の正規化 ─────────────────────────────────────────────────────────────

def to_snake(raw, prefix):
    """TD 命名規則（英小文字・数字・_）に寄せる。英数字が無ければ空文字を返す"""
    s = re.sub(r"[^a-z0-9]+", "_", str(raw).strip().lower()).strip("_")
    if s and s[0].isdigit():
        s = f"{prefix}_{s}"
    return s


def header_key(raw):
    if isinstance(raw, datetime):
        return raw.strftime("date %Y %m %d")
    return "" if raw is None else str(raw).strip()


def unique(names):
    seen = {}
    out = []
    for n in names:
        seen[n] = seen.get(n, 0) + 1
        out.append(n if seen[n] == 1 else f"{n}_{seen[n]}")
    return out


def header_keys(rows, header_idx, width, combine):
    """各列のヘッダー文字列。combine のときは1行上のカテゴリと「カテゴリ_項目」で結合する"""
    items = [header_key(rows[header_idx][i] if i < len(rows[header_idx]) else None) for i in range(width)]
    if not combine or header_idx == 0:
        return items
    cat_row = rows[header_idx - 1]
    keys, cat = [], ""
    for i, item in enumerate(items):
        raw = header_key(cat_row[i] if i < len(cat_row) else None)
        cat = raw or cat
        keys.append("_".join(x for x in (cat, item) if x))
    return keys


def build_header(keys, col_map, warnings):
    names = []
    for i, key in enumerate(keys):
        if key in col_map:
            names.append(col_map[key])
            continue
        name = to_snake(key, "col") if key else ""
        if not name:
            name = f"column_{i + 1}"
            label = f"「{key}」" if key else "（ヘッダーなし）"
            warnings.append(f"列{i + 1}{label} → {name}（英数字にできないため。column_maps で指定できます）")
        names.append(name)
    return unique(names)


# ── シートの処理 ─────────────────────────────────────────────────────────────

def detect_data_end(rows, header_idx, limit):
    """ヘッダーの次の行から見て、空行が limit 行連続した地点でデータを打ち切る。
    20行未満の空行は区切りとして残す（後段で空行はスキップされる）。
    戻り値: (データ終端の次の index, 除外された非空行, 打ち切ったか)"""
    last_content = header_idx
    run = 0
    cut = False
    for i in range(header_idx + 1, len(rows)):
        if is_blank_row(rows[i]):
            run += 1
            if run >= limit:
                cut = True
                break
        else:
            run = 0
            last_content = i
    end = last_content + 1
    dropped = [r for r in rows[end:] if not is_blank_row(r)] if cut else []
    return end, dropped, cut


def effective_width(rows, header_idx, end):
    """ヘッダーからデータ末尾までの範囲で、非空のセルがある最大列数"""
    width = 0
    for r in rows[header_idx:end]:
        for c, v in enumerate(r):
            if not is_blank(v):
                width = max(width, c + 1)
    return width


def infer_column_types(records, width):
    return [infer_type([normalize_value(r[i]) for r in records]) for i in range(width)]


def build_table(sheet_name, table, rows, header_idx, combine, limit, col_map, out_dir, excel_name):
    end, dropped, cut = detect_data_end(rows, header_idx, limit)
    width = effective_width(rows, header_idx, end)
    warnings = []
    header = build_header(header_keys(rows, header_idx, width, combine), col_map, warnings)
    for i, name in enumerate(header):
        if name in RESERVED_COLUMNS:
            header[i] = f"{name}_src"
            warnings.append(f"列『{name}』は予約カラムと重複するため『{name}_src』に変更")

    records = [r[:width] for r in rows[header_idx + 1:end] if not is_blank_row(r)]
    if not records or width == 0:
        return None

    types = infer_column_types(records, width)
    csv_path = os.path.join(out_dir, f"{table}.csv")
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header + FIXED_COLUMNS)
        for r in records:
            w.writerow([csv_text(normalize_value(v)) for v in r] + [excel_name, sheet_name])

    return {
        "sheet": sheet_name,
        "table": table,
        "csv": f"{table}.csv",
        "header_row_excel": header_idx + 1,
        "data_rows_excel": [header_idx + 2, end],
        "data_rows": len(records),
        "cut": cut,
        "cut_at_row_excel": end + 1 if cut else None,
        "dropped_text_rows": len(dropped),
        "dropped_preview": first_text(dropped[0])[:60] if dropped else "",
        "warnings": warnings,
        "columns": [{"name": h, "type": t} for h, t in zip(header, types)]
                   + [{"name": c, "type": "VARCHAR"} for c in FIXED_COLUMNS],
    }


def inspect(z, sheet_paths, shared, date_ids, limit):
    """シートごとの規模・先頭行・打ち切り候補を表示する（ファイルは書かない）"""
    for n, (sheet_name, path) in enumerate(sheet_paths.items(), 1):
        rows = read_sheet_grid(z, path, shared, date_ids)
        filled = [i for i, r in enumerate(rows) if not is_blank_row(r)]
        print(f"[{n}] {sheet_name}")
        if not filled:
            print("  空シート")
            continue
        first = filled[0]
        end, dropped, cut = detect_data_end(rows, first, limit)
        width = effective_width(rows, first, end)
        print(f"  非空行 {len(filled):,} / 列 {width} / 最初の非空行 {first + 1}行目")
        for i in filled[:3]:
            cells = [csv_text(normalize_value(v)) for v in rows[i][:width]]
            print(f"  {i + 1}行目: {cells[:8]}{' …' if width > 8 else ''}")
        if cut:
            print(f"  空行{limit}行連続のため {end + 1}行目以降は除外予定（非空行 {len(dropped)}行・先頭「{first_text(dropped[0])[:40]}」）")


def load_config(path):
    if not path:
        return {}
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def main():
    ap = argparse.ArgumentParser(description="Excel → CSV + manifest.json")
    ap.add_argument("xlsx")
    ap.add_argument("out_dir", nargs="?")
    ap.add_argument("--inspect", action="store_true", help="シートの下見のみ（ファイルは書かない）")
    ap.add_argument("--config", help="シート設定 JSON（省略時は全シート）")
    args = ap.parse_args()

    cfg = load_config(args.config)
    limit = cfg.get("blank_run_limit", DEFAULT_BLANK_RUN_LIMIT)
    col_maps = cfg.get("column_maps", {})
    excel_name = os.path.basename(args.xlsx)
    if not args.inspect and not args.out_dir:
        ap.error("out_dir を指定してください（下見だけなら --inspect）")

    with zipfile.ZipFile(args.xlsx) as z:
        shared = load_shared_strings(z)
        date_ids = load_date_style_ids(z)
        sheet_paths = dict(list_sheets(z))
        if args.inspect:
            inspect(z, sheet_paths, shared, date_ids, limit)
            return
        os.makedirs(args.out_dir, exist_ok=True)
        plan = cfg.get("sheets") or {name: {} for name in sheet_paths}

        tables, skipped, used = [], [], set()
        for n, (sheet_name, opts) in enumerate(plan.items(), 1):
            if sheet_name not in sheet_paths:
                skipped.append((sheet_name, "シートが見つからない"))
                continue
            table = opts.get("table") or to_snake(sheet_name, "t") or f"sheet_{n}"
            if table in used:
                skipped.append((sheet_name, f"テーブル名が重複: {table}"))
                continue
            used.add(table)
            rows = read_sheet_grid(z, sheet_paths[sheet_name], shared, date_ids)
            header_idx = opts.get("header_row", 0)
            if header_idx >= len(rows) or is_blank_row(rows[header_idx]):
                skipped.append((sheet_name, "ヘッダー行が空"))
                continue
            entry = build_table(sheet_name, table, rows, header_idx, opts.get("combine_category_row", False),
                                limit, col_maps.get(table, {}), args.out_dir, excel_name)
            if entry is None:
                skipped.append((sheet_name, "データ行なし"))
            else:
                tables.append(entry)

    # シートごとの確認表示
    for t in tables:
        print(f"[{t['sheet']}] → {t['table']}")
        print(f"  ヘッダー {t['header_row_excel']}行目 / データ {t['data_rows_excel'][0]}〜{t['data_rows_excel'][1]}行 / {t['data_rows']:,}件")
        if t["cut"]:
            print(f"  空行{limit}行連続のため {t['cut_at_row_excel']}行目以降を除外（非空行 {t['dropped_text_rows']}行）")
            if t["dropped_preview"]:
                print(f"  除外の先頭: 「{t['dropped_preview']}」")
        for w in t["warnings"]:
            print(f"  ! {w}")
        print(f"  → {os.path.join(args.out_dir, t['csv'])}")
    for name, reason in skipped:
        print(f"[{name}] スキップ: {reason}")

    manifest = {
        "source_file": excel_name,
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "blank_run_limit": limit,
        "tables": tables,
        "skipped": [{"sheet": s, "reason": r} for s, r in skipped],
    }
    with open(os.path.join(args.out_dir, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
    print(f"\nmanifest: {os.path.join(args.out_dir, 'manifest.json')}")


if __name__ == "__main__":
    main()
