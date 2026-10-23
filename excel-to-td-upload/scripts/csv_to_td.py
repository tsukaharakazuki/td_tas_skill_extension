#!/usr/bin/env python3
"""
CSV + manifest.json → Treasure Data（Bulk Import API・標準ライブラリのみ）

使い方:
  python3 csv_to_td.py <out_dir> --database <db>                  # 実行計画の表示のみ（TD には書き込まない）
  python3 csv_to_td.py <out_dir> --database <db> --execute        # 取り込み実行
  オプション: --mode overwrite|append（既定 overwrite） --tables a,b --part-rows 100000 --env .env

  python3 csv_to_td.py <out_dir> --database <db> --check          # 書き込みなしで認証と Bulk Import API の可否を確認

認証（環境変数または .env。値は表示しない）:
  TD_API_KEY=<書き込み権限のある API キー>        # 無ければ TDX_ACCESS_TOKEN（TAS の tdx 用トークン）を使う
  TD_ENDPOINT=https://api.treasuredata.com      # 無ければ TDX_SITE（us01 / jp01 / eu01 / ap02）から決める
  TD_AUTH_SCHEME=TD1 | Bearer                   # 省略時は自動判定（ACCOUNT_ID/KEY 形式なら TD1）

上書き（overwrite）は一時テーブルに取り込んでから swap するため、途中で失敗しても既存テーブルは壊れない。
"""
import argparse
import csv
import gzip
import io
import json
import os
import re
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

TD_TYPES = {"BIGINT": "long", "DOUBLE": "double", "VARCHAR": "string"}
SITE_ENDPOINTS = {
    "us01": "https://api.treasuredata.com",
    "jp01": "https://api.treasuredata.co.jp",
    "eu01": "https://api.eu01.treasuredata.com",
    "ap02": "https://api.ap02.treasuredata.com",
}
API_KEY_PATTERN = re.compile(r"\d+/[0-9A-Za-z]+")
RETRY_STATUS = {429, 500, 502, 503, 504}
POLL_INTERVAL_SEC = 10
POLL_TIMEOUT_SEC = 6 * 3600


# ── msgpack（取り込みに必要な型だけ） ────────────────────────────────────────

def pack(v, out):
    if v is None:
        out.append(b"\xc0")
    elif v is True:
        out.append(b"\xc3")
    elif v is False:
        out.append(b"\xc2")
    elif isinstance(v, int):
        if 0 <= v < 0x80:
            out.append(struct.pack("B", v))
        elif -32 <= v < 0:
            out.append(struct.pack("b", v))
        elif 0 <= v < 1 << 64:
            out.append(b"\xcf" + struct.pack(">Q", v))
        elif -(1 << 63) <= v < 0:
            out.append(b"\xd3" + struct.pack(">q", v))
        else:
            pack(str(v), out)  # 範囲外の整数は文字列にする（公式クライアントと同じ扱い）
    elif isinstance(v, float):
        out.append(b"\xcb" + struct.pack(">d", v))
    elif isinstance(v, str):
        b = v.encode("utf-8")
        n = len(b)
        if n < 32:
            out.append(struct.pack("B", 0xA0 | n))
        elif n < 1 << 8:
            out.append(b"\xd9" + struct.pack("B", n))
        elif n < 1 << 16:
            out.append(b"\xda" + struct.pack(">H", n))
        else:
            out.append(b"\xdb" + struct.pack(">I", n))
        out.append(b)
    elif isinstance(v, dict):
        n = len(v)
        if n < 16:
            out.append(struct.pack("B", 0x80 | n))
        elif n < 1 << 16:
            out.append(b"\xde" + struct.pack(">H", n))
        else:
            out.append(b"\xdf" + struct.pack(">I", n))
        for k, val in v.items():
            pack(k, out)
            pack(val, out)
    else:
        raise TypeError(f"msgpack 非対応の型: {type(v)}")


def pack_records_gz(records):
    out = []
    for r in records:
        pack(r, out)
    return gzip.compress(b"".join(out))


# ── TD REST API ─────────────────────────────────────────────────────────────

class TDError(Exception):
    pass


class TD:
    def __init__(self, token, endpoint, scheme=None):
        self.token = token
        self.base = endpoint.rstrip("/")
        # API キー（ACCOUNT_ID/KEY）は TD1、それ以外（TAS の OAuth トークン等）は Bearer
        self.scheme = scheme or ("TD1" if API_KEY_PATTERN.fullmatch(token) else "Bearer")

    def call(self, method, path, data=None, form=None, query=None, ok404=False, retries=5):
        url = f"{self.base}/v3/{path}"
        if query:
            url += "?" + urllib.parse.urlencode(query)
        headers = {"Authorization": f"{self.scheme} {self.token}"}
        body = data
        if form is not None:
            body = urllib.parse.urlencode(form).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        elif data is not None:
            headers["Content-Type"] = "application/octet-stream"
        elif method in ("POST", "PUT"):
            body = b""
        for attempt in range(retries + 1):
            req = urllib.request.Request(url, data=body, method=method, headers=headers)
            try:
                with urllib.request.urlopen(req, timeout=600) as res:
                    text = res.read().decode("utf-8") or "{}"
                    return json.loads(text)
            except urllib.error.HTTPError as e:
                if e.code == 404 and ok404:
                    return None
                detail = e.read().decode("utf-8", "replace")[:300]
                if e.code in RETRY_STATUS and attempt < retries:
                    time.sleep(min(2 ** attempt * 2, 60))
                    continue
                raise TDError(f"{method} /v3/{path} → HTTP {e.code}: {detail}") from None
            except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
                if attempt < retries:
                    time.sleep(min(2 ** attempt * 2, 60))
                    continue
                raise TDError(f"{method} /v3/{path} → 通信エラー: {e}") from None

    def q(self, s):
        return urllib.parse.quote(s, safe="")

    def table_show(self, db, table):
        return self.call("GET", f"table/show/{self.q(db)}/{self.q(table)}", ok404=True)

    def table_create(self, db, table, schema):
        self.call("POST", f"table/create/{self.q(db)}/{self.q(table)}", form={"schema": json.dumps(schema)})

    def table_delete(self, db, table):
        self.call("POST", f"table/delete/{self.q(db)}/{self.q(table)}")

    def table_swap(self, db, t1, t2):
        self.call("POST", f"table/swap/{self.q(db)}/{self.q(t1)}/{self.q(t2)}")

    def bi(self, action, name, extra=""):
        method = "GET" if action == "show" else "POST"
        return self.call(method, f"bulk_import/{action}/{self.q(name)}{extra}", ok404=(action == "show"))

    def bi_create(self, name, db, table):
        self.call("POST", f"bulk_import/create/{self.q(name)}/{self.q(db)}/{self.q(table)}")

    def bi_upload_part(self, name, part, payload):
        self.call("PUT", f"bulk_import/upload_part/{self.q(name)}/{self.q(part)}", data=payload)


# ── 入力 ─────────────────────────────────────────────────────────────────────

def load_env(path):
    env = {}
    if path and os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip().strip('"').strip("'")
    for k in ("TD_API_KEY", "TD_ENDPOINT", "TD_AUTH_SCHEME", "TDX_ACCESS_TOKEN", "TDX_SITE"):
        if os.environ.get(k):
            env[k] = os.environ[k]
    # TAS: TD_API_KEY が無ければ tdx 用のトークン（TDX_ACCESS_TOKEN）、接続先は TDX_SITE から決める
    env.setdefault("TD_API_KEY", env.get("TDX_ACCESS_TOKEN"))
    if not env.get("TD_ENDPOINT") and env.get("TDX_SITE"):
        env["TD_ENDPOINT"] = SITE_ENDPOINTS.get(env["TDX_SITE"])
    return env


def check_connection(td, db):
    """書き込みなしで、認証・DB・Bulk Import API の利用可否を確認する"""
    print(f"接続確認: {td.base}（認証方式 {td.scheme}）")
    ok = True
    for label, path in [("データベース参照", f"database/show/{td.q(db)}"), ("Bulk Import API（一覧取得）", "bulk_import/list")]:
        try:
            td.call("GET", path, retries=1)
            print(f"  OK  {label}")
        except TDError as e:
            ok = False
            print(f"  NG  {label}: {e}")
    print("→ 取り込みできる見込みです（--execute で実行）" if ok else "→ 上の NG を解消してください（Bulk Import が NG なら API キーが必要）")
    return ok


def convert(value, col_type):
    if value == "":
        return None
    if col_type == "BIGINT":
        return int(value)
    if col_type == "DOUBLE":
        return float(value)
    return value


def iter_parts(csv_path, columns, part_rows, now_ts):
    """CSV を part_rows 行ずつ (records, 行番号範囲) にして返す"""
    types = {c["name"]: c["type"] for c in columns}
    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader)
        missing = [h for h in header if h not in types]
        if missing:
            raise ValueError(f"manifest に無い列: {missing}")
        batch, start = [], 1
        for n, row in enumerate(reader, 1):
            rec = {"time": now_ts}
            for h, v in zip(header, row):
                rec[h] = convert(v, types[h])
            batch.append(rec)
            if len(batch) >= part_rows:
                yield batch, (start, n)
                batch, start = [], n + 1
        if batch:
            yield batch, (start, start + len(batch) - 1)


def td_schema(columns):
    return [[c["name"], TD_TYPES[c["type"]]] for c in columns]


# ── 進捗 ─────────────────────────────────────────────────────────────────────

def load_progress(path):
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    return {}


def save_progress(path, progress):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(progress, f, ensure_ascii=False, indent=2)
    os.replace(tmp, path)


# ── Bulk Import 1 テーブル分 ─────────────────────────────────────────────────

def wait_status(td, name, targets, label):
    deadline = time.time() + POLL_TIMEOUT_SEC
    while time.time() < deadline:
        info = td.bi("show", name)
        if info is None:
            raise TDError(f"セッション {name} が見つからない")
        if info.get("status") in targets:
            return info
        print(f"    {label}中… status={info.get('status')}", flush=True)
        time.sleep(POLL_INTERVAL_SEC)
    raise TDError(f"{label}がタイムアウト（{POLL_TIMEOUT_SEC // 3600}時間）")


def bulk_import(td, db, table, csv_path, columns, part_rows, now_ts, expected_rows, allow_errors):
    session = f"{db}_{table}_{int(time.time())}"[:100]
    td.bi_create(session, db, table)
    print(f"  セッション作成: {session}")
    try:
        sent = 0
        for i, (records, (a, b)) in enumerate(iter_parts(csv_path, columns, part_rows, now_ts), 1):
            payload = pack_records_gz(records)
            td.bi_upload_part(session, f"part_{i:05d}", payload)
            sent += len(records)
            print(f"    part_{i:05d}: {a:,}〜{b:,}行 ({len(payload) / 1048576:.1f} MB) 送信 → 累計 {sent:,}/{expected_rows:,}", flush=True)
        td.bi("freeze", session)
        td.bi("perform", session)
        info = wait_status(td, session, {"ready"}, "取り込みジョブ")
        valid, errors = info.get("valid_records", 0), info.get("error_records", 0)
        print(f"  取り込み結果: 有効 {valid:,}件 / エラー {errors:,}件（送信 {sent:,}件）")
        if valid == 0:
            raise TDError("有効なレコードが 0 件")
        if errors and not allow_errors:
            raise TDError(f"エラーレコードが {errors:,} 件あるため commit を中止（--allow-errors で許可）")
        td.bi("commit", session)
        wait_status(td, session, {"committed"}, "commit")
        return valid, errors
    finally:
        td.bi("delete", session)  # 成功・失敗どちらでもセッションは消す（データは commit 済みなら残る）


def import_table(td, db, entry, out_dir, mode, part_rows, allow_errors):
    table = entry["table"]
    columns = entry["columns"]
    csv_path = os.path.join(out_dir, entry["csv"])
    now_ts = int(time.time())
    schema = td_schema(columns)

    if mode == "append":
        if td.table_show(db, table) is None:
            td.table_create(db, table, schema)
            print(f"  テーブル作成: {db}.{table}")
        return bulk_import(td, db, table, csv_path, columns, part_rows, now_ts, entry["data_rows"], allow_errors)

    # overwrite: 一時テーブル → swap → 旧データ（一時テーブル側）を削除
    tmp = f"{table}_tmp_{now_ts}"
    td.table_create(db, tmp, schema)
    print(f"  一時テーブル作成: {db}.{tmp}")
    try:
        result = bulk_import(td, db, tmp, csv_path, columns, part_rows, now_ts, entry["data_rows"], allow_errors)
    except Exception:
        td.table_delete(db, tmp)
        print(f"  一時テーブル削除: {db}.{tmp}（失敗のため。既存テーブルは変更なし）")
        raise
    if td.table_show(db, table) is None:
        td.table_create(db, table, schema)
    td.table_swap(db, table, tmp)
    td.table_delete(db, tmp)
    print(f"  swap して差し替え: {db}.{table}（旧データは削除）")
    return result


# ── main ─────────────────────────────────────────────────────────────────────

def print_plan(manifest, targets, db, mode, part_rows, endpoint, key_ok, out_dir):
    print(f"取り込み先: {db}（{endpoint or 'TD_ENDPOINT 未設定'}）/ モード: {mode} / 1パート {part_rows:,}行")
    print(f"認証情報: {'設定あり' if key_ok else '未設定（TD_API_KEY または TDX_ACCESS_TOKEN）'}")
    total = 0
    for t in targets:
        size = os.path.getsize(os.path.join(out_dir, t["csv"])) / 1048576
        parts = -(-t["data_rows"] // part_rows)
        total += t["data_rows"]
        cols = ", ".join(f"{c['name']}:{c['type']}" for c in t["columns"])
        print(f"  [{t['sheet']}] → {db}.{t['table']}  {t['data_rows']:,}行 / CSV {size:.1f} MB / {parts}パート")
        print(f"    列: time:BIGINT（取り込み時刻）, {cols}")
    print(f"合計 {total:,}行 / {len(targets)}テーブル")
    if mode == "overwrite":
        print("※ overwrite: 既存テーブルの中身は新しいデータで置き換わります")


def main():
    ap = argparse.ArgumentParser(description="CSV + manifest.json → TD（Bulk Import）")
    ap.add_argument("out_dir", help="excel_to_csv.py の出力フォルダ")
    ap.add_argument("--database", required=True)
    ap.add_argument("--mode", choices=["overwrite", "append"], default="overwrite")
    ap.add_argument("--tables", help="取り込むテーブル（カンマ区切り。省略時は全部）")
    ap.add_argument("--part-rows", type=int, default=100_000)
    ap.add_argument("--env", default=".env", help=".env のパス（既定: カレントの .env）")
    ap.add_argument("--allow-errors", action="store_true", help="エラーレコードがあっても commit する")
    ap.add_argument("--execute", action="store_true", help="実際に取り込む（省略時は計画の表示のみ）")
    ap.add_argument("--check", action="store_true", help="書き込みなしで認証と Bulk Import API の利用可否だけ確認する")
    args = ap.parse_args()

    with open(os.path.join(args.out_dir, "manifest.json"), encoding="utf-8") as f:
        manifest = json.load(f)
    targets = manifest["tables"]
    if args.tables:
        wanted = {t.strip() for t in args.tables.split(",")}
        unknown = wanted - {t["table"] for t in targets}
        if unknown:
            sys.exit(f"manifest に無いテーブル: {sorted(unknown)}")
        targets = [t for t in targets if t["table"] in wanted]

    env = load_env(args.env)
    apikey, endpoint = env.get("TD_API_KEY"), env.get("TD_ENDPOINT")
    if args.check:
        if not apikey or not endpoint:
            sys.exit("認証情報または接続先が未設定です（TD_API_KEY か TDX_ACCESS_TOKEN、TD_ENDPOINT か TDX_SITE）")
        sys.exit(0 if check_connection(TD(apikey, endpoint, env.get("TD_AUTH_SCHEME")), args.database) else 1)
    progress_path = os.path.join(args.out_dir, f"upload_progress_{args.database}.json")
    progress = load_progress(progress_path)
    done = [t for t in targets if progress.get(t["table"], {}).get("status") == "done"]
    targets = [t for t in targets if t not in done]
    for t in done:
        print(f"[{t['table']}] 完了済みのためスキップ（やり直す場合は {os.path.basename(progress_path)} から削除）")

    print_plan(manifest, targets, args.database, args.mode, args.part_rows, endpoint, bool(apikey), args.out_dir)
    if not args.execute:
        print("\n計画の表示のみです。取り込むには --execute を付けて実行してください。")
        return
    if not apikey or not endpoint:
        sys.exit("TD_API_KEY / TD_ENDPOINT が未設定です（.env を確認）")

    td = TD(apikey, endpoint, env.get("TD_AUTH_SCHEME"))
    failed = []
    for t in targets:
        print(f"\n[{t['sheet']}] → {args.database}.{t['table']}")
        started = time.time()
        try:
            valid, errors = import_table(td, args.database, t, args.out_dir, args.mode, args.part_rows, args.allow_errors)
            progress[t["table"]] = {"status": "done", "valid_records": valid, "error_records": errors,
                                    "mode": args.mode, "finished_at": time.strftime("%Y-%m-%dT%H:%M:%S")}
            print(f"  完了（{time.time() - started:.0f}秒）")
        except Exception as e:
            progress[t["table"]] = {"status": "failed", "error": str(e)[:500]}
            failed.append(t["table"])
            print(f"  失敗: {e}")
        save_progress(progress_path, progress)

    print(f"\n完了 {len(targets) - len(failed)} / 失敗 {len(failed)}" + (f": {', '.join(failed)}" if failed else ""))
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
