"""excel_to_csv.py / csv_to_td.py のテスト（標準ライブラリのみ・TD には接続しない）

  python3 -m unittest discover -s tests -v
"""
import csv
import gzip
import io
import json
import os
import struct
import subprocess
import sys
import tempfile
import threading
import unittest
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlparse
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.join(HERE, "..", "scripts")
sys.path.insert(0, SCRIPTS)
import csv_to_td  # noqa: E402

csv_to_td.POLL_INTERVAL_SEC = 0


# ── テスト用 xlsx（最小構成） ─────────────────────────────────────────────────

DATE = object()  # セル値に (DATE, シリアル値) で日付書式を付ける


def col_letters(i):
    s = ""
    i += 1
    while i:
        i, r = divmod(i - 1, 26)
        s = chr(65 + r) + s
    return s


def cell_xml(ref, v):
    if v is None:
        return ""
    if isinstance(v, tuple) and v[0] is DATE:
        return f'<c r="{ref}" s="1"><v>{v[1]}</v></c>'
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        return f'<c r="{ref}"><v>{v}</v></c>'
    return f'<c r="{ref}" t="inlineStr"><is><t xml:space="preserve">{escape(str(v))}</t></is></c>'


def make_xlsx(path, sheets):
    ns = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
    rel_ns = 'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
    with zipfile.ZipFile(path, "w") as z:
        sheet_tags, rels = [], []
        for n, (name, rows) in enumerate(sheets.items(), 1):
            body = "".join(
                f'<row r="{r + 1}">' + "".join(cell_xml(f"{col_letters(c)}{r + 1}", v) for c, v in enumerate(row)) + "</row>"
                for r, row in enumerate(rows))
            z.writestr(f"xl/worksheets/sheet{n}.xml", f"<worksheet {ns}><sheetData>{body}</sheetData></worksheet>")
            sheet_tags.append(f'<sheet name="{escape(name)}" sheetId="{n}" r:id="rId{n}"/>')
            rels.append(f'<Relationship Id="rId{n}" Type="worksheet" Target="worksheets/sheet{n}.xml"/>')
        z.writestr("xl/workbook.xml", f"<workbook {ns} {rel_ns}><sheets>{''.join(sheet_tags)}</sheets></workbook>")
        z.writestr("xl/_rels/workbook.xml.rels",
                   '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                   + "".join(rels) + "</Relationships>")
        z.writestr("xl/styles.xml", f'<styleSheet {ns}><cellXfs count="2"><xf numFmtId="0"/><xf numFmtId="14"/></cellXfs></styleSheet>')


def run_excel_to_csv(*args):
    r = subprocess.run([sys.executable, os.path.join(SCRIPTS, "excel_to_csv.py"), *args],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise AssertionError(r.stderr)
    return r.stdout


def read_csv(path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.reader(f))


# ── Excel → CSV ─────────────────────────────────────────────────────────────

class ExcelToCsvTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.xlsx = os.path.join(self.tmp, "売上.xlsx")

    def convert(self, sheets, config=None):
        make_xlsx(self.xlsx, sheets)
        out = os.path.join(self.tmp, "out")
        args = [self.xlsx, out]
        if config:
            cfg = os.path.join(self.tmp, "config.json")
            with open(cfg, "w", encoding="utf-8") as f:
                json.dump(config, f, ensure_ascii=False)
            args += ["--config", cfg]
        stdout = run_excel_to_csv(*args)
        with open(os.path.join(out, "manifest.json"), encoding="utf-8") as f:
            return out, json.load(f), stdout

    def test_blank_run_cut_at_20_rows(self):
        rows = [["id", "name"], [1, "A"]] + [[None, None]] * 19 + [[2, "B"]] + [["", " "]] * 20 + [["※ 注記", None]]
        out, m, stdout = self.convert({"s": rows})
        t = m["tables"][0]
        self.assertEqual(t["data_rows"], 2)          # 19行の空行は区切りとして残る
        self.assertTrue(t["cut"])                     # 空文字・空白だけの行 20行で打ち切り
        self.assertEqual(t["dropped_preview"], "※ 注記")
        self.assertIn("除外の先頭", stdout)
        self.assertEqual(read_csv(os.path.join(out, t["csv"]))[1:], [["1", "A", "売上.xlsx", "s"], ["2", "B", "売上.xlsx", "s"]])

    def test_header_row_types_and_reserved_names(self):
        rows = [["一覧"], ["time", "amount", "rate", "day", "excel_name"],
                [1, 10, 1.5, (DATE, 46296), "x"], [2, 20, 2, (DATE, 46297), "y"]]
        out, m, _ = self.convert({"s": rows}, {"sheets": {"s": {"table": "t1", "header_row": 1}}})
        cols = {c["name"]: c["type"] for c in m["tables"][0]["columns"]}
        self.assertEqual(cols["time_src"], "BIGINT")   # time は予約カラムなので改名
        self.assertEqual(cols["excel_name_src"], "VARCHAR")
        self.assertEqual(cols["amount"], "BIGINT")
        self.assertEqual(cols["rate"], "DOUBLE")
        self.assertEqual(cols["day"], "VARCHAR")
        self.assertEqual(read_csv(os.path.join(out, "t1.csv"))[1][3], "2026-10-01T00:00:00")

    def test_japanese_headers_need_column_maps(self):
        rows = [["申込日", "店舗名"], ["2026-10-01", "渋谷"]]
        _, m, stdout = self.convert({"シート": rows})
        self.assertEqual([c["name"] for c in m["tables"][0]["columns"]][:2], ["column_1", "column_2"])
        self.assertIn("column_maps", stdout)
        _, m, _ = self.convert({"シート": rows}, {"sheets": {"シート": {"table": "apps"}},
                                                  "column_maps": {"apps": {"申込日": "application_date", "店舗名": "store_name"}}})
        self.assertEqual([c["name"] for c in m["tables"][0]["columns"]][:2], ["application_date", "store_name"])

    def test_combine_category_row(self):
        rows = [[None, "カート落ち", None, "購入", None], ["日付", "件数", "金額", "件数", "金額"], ["d1", 1, 100, 2, 200]]
        cfg = {"sheets": {"s": {"table": "funnel", "header_row": 1, "combine_category_row": True}},
               "column_maps": {"funnel": {"日付": "date", "カート落ち_件数": "cart_count", "カート落ち_金額": "cart_amount",
                                          "購入_件数": "purchase_count", "購入_金額": "purchase_amount"}}}
        _, m, _ = self.convert({"s": rows}, cfg)
        self.assertEqual([c["name"] for c in m["tables"][0]["columns"]][:5],
                         ["date", "cart_count", "cart_amount", "purchase_count", "purchase_amount"])

    def test_inspect_writes_nothing(self):
        make_xlsx(self.xlsx, {"a": [["x"], [1]], "空": []})
        stdout = run_excel_to_csv(self.xlsx, "--inspect")
        self.assertIn("[2] 空", stdout)
        self.assertIn("空シート", stdout)
        self.assertEqual(sorted(os.listdir(self.tmp)), ["売上.xlsx"])


# ── msgpack ─────────────────────────────────────────────────────────────────

def unpack_all(data):
    """テスト用の最小 msgpack デコーダ（csv_to_td.pack が出す型だけ）"""
    pos = 0

    def read(n):
        nonlocal pos
        b = data[pos:pos + n]
        pos += n
        return b

    def one():
        t = read(1)[0]
        if t <= 0x7F:
            return t
        if t >= 0xE0:
            return t - 0x100
        if 0xA0 <= t <= 0xBF:
            return read(t & 0x1F).decode()
        if 0x80 <= t <= 0x8F:
            return {one(): one() for _ in range(t & 0x0F)}
        simple = {0xC0: None, 0xC2: False, 0xC3: True}
        if t in simple:
            return simple[t]
        fmt = {0xCB: ">d", 0xCF: ">Q", 0xD3: ">q"}
        if t in fmt:
            return struct.unpack(fmt[t], read(8))[0]
        lens = {0xD9: ">B", 0xDA: ">H", 0xDB: ">I", 0xDE: ">H", 0xDF: ">I"}
        n = struct.unpack(lens[t], read(struct.calcsize(lens[t])))[0]
        if t in (0xDE, 0xDF):
            return {one(): one() for _ in range(n)}
        return read(n).decode()

    out = []
    while pos < len(data):
        out.append(one())
    return out


class MsgpackTest(unittest.TestCase):
    def test_roundtrip(self):
        cases = [None, True, False, 0, 127, 128, 2 ** 63, 2 ** 64 - 1, -1, -32, -33, -2 ** 63, 1.5, -0.25,
                 "", "あ" * 11, "x" * 32, "x" * 300, "x" * 70000, {"time": 1, "k": None}, {f"k{i}": i for i in range(20)}]
        for v in cases:
            buf = []
            csv_to_td.pack(v, buf)
            self.assertEqual(unpack_all(b"".join(buf)), [v], repr(v)[:30])

    def test_out_of_range_int_becomes_string(self):
        buf = []
        csv_to_td.pack(2 ** 64, buf)
        self.assertEqual(unpack_all(b"".join(buf)), [str(2 ** 64)])


# ── 模擬 TD サーバー ─────────────────────────────────────────────────────────

class MockTD:
    def __init__(self, reject_bearer_bulk=False, error_table_prefix=""):
        self.tables = {"db.t": {"rows": [{"old": 1}]}}
        self.sessions, self.calls, self.auth = {}, [], set()
        self.reject_bearer_bulk, self.error_table_prefix = reject_bearer_bulk, error_table_prefix
        mock = self

        class H(BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def reply(self, code, obj):
                b = json.dumps(obj).encode()
                self.send_response(code)
                self.send_header("Content-Length", str(len(b)))
                self.end_headers()
                self.wfile.write(b)

            def handle_any(self):
                body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
                code, obj = mock.route(self.command, urlparse(self.path).path, self.headers.get("Authorization", ""), body)
                self.reply(code, obj)

            do_GET = do_POST = do_PUT = handle_any

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), H)
        self.url = f"http://127.0.0.1:{self.server.server_port}"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def close(self):
        self.server.shutdown()
        self.server.server_close()

    def route(self, method, path, auth, body):
        p = [unquote(x) for x in path.split("/")[2:]]
        self.calls.append(f"{p[0]}/{p[1]}")
        self.auth.add(auth.split(" ")[0])
        if self.reject_bearer_bulk and auth.startswith("Bearer ") and p[0] == "bulk_import":
            return 403, {"error": "API key required"}
        kind, action = p[0], p[1]
        if kind == "database":
            return (200, {}) if p[2] == "db" else (404, {})
        if kind == "table":
            key = f"{p[2]}.{p[3]}"
            if action == "show":
                return (200, {}) if key in self.tables else (404, {})
            if action == "create":
                self.tables[key] = {"rows": [], "schema": json.loads(parse_qs(body.decode())["schema"][0])}
                return 200, {}
            if action == "delete":
                self.tables.pop(key, None)
                return 200, {}
            if action == "swap":
                k2 = f"{p[2]}.{p[4]}"
                self.tables[key], self.tables[k2] = self.tables[k2], self.tables[key]
                return 200, {}
        if kind == "bulk_import":
            if action == "list":
                return 200, {"bulk_imports": []}
            if action == "create":
                self.sessions[p[2]] = {"table": f"{p[3]}.{p[4]}", "records": [], "status": "uploading"}
                return 200, {}
            s = self.sessions[p[2]]
            if action == "upload_part":
                s["records"] += unpack_all(gzip.decompress(body))
            elif action == "perform":
                s["status"] = "ready"
            elif action == "commit":
                self.tables[s["table"]]["rows"] += s["records"]
                s["status"] = "committed"
            elif action == "delete":
                del self.sessions[p[2]]
            elif action == "show":
                bad = self.error_table_prefix and s["table"].split(".")[1].startswith(self.error_table_prefix)
                return 200, {"status": s["status"], "valid_records": len(s["records"]), "error_records": 2 if bad else 0}
            return 200, {}
        return 400, {}


class CsvToTdTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        xlsx = os.path.join(self.tmp, "book.xlsx")
        make_xlsx(xlsx, {"A": [["id", "v"], [1, "x"], [2, None], [3, "z"]], "B": [["k"], ["a"]]})
        cfg = os.path.join(self.tmp, "cfg.json")
        with open(cfg, "w") as f:
            json.dump({"sheets": {"A": {"table": "t"}, "B": {"table": "u"}}}, f)
        self.out = os.path.join(self.tmp, "out")
        run_excel_to_csv(xlsx, self.out, "--config", cfg)

    def run_cli(self, mock, *args, token="123/abc"):
        env = {"TD_API_KEY": token, "TD_ENDPOINT": mock.url}
        old_env, old_argv = dict(os.environ), sys.argv
        os.environ.update(env)
        sys.argv = ["csv_to_td.py", self.out, "--database", "db", "--env", "/nonexistent", *args]
        try:
            with self.assertRaises(SystemExit) as cm:
                csv_to_td.main()
                raise SystemExit(0)
            return cm.exception.code or 0
        finally:
            os.environ.clear()
            os.environ.update(old_env)
            sys.argv = old_argv

    def test_plan_only_does_not_call_api(self):
        mock = MockTD()
        self.addCleanup(mock.close)
        self.assertEqual(self.run_cli(mock), 0)
        self.assertEqual(mock.calls, [])

    def test_overwrite_swaps_and_failure_keeps_existing(self):
        mock = MockTD(error_table_prefix="u")
        self.addCleanup(mock.close)
        self.assertEqual(self.run_cli(mock, "--execute", "--part-rows", "2"), 1)  # u は失敗
        rows = mock.tables["db.t"]["rows"]
        self.assertEqual([r["id"] for r in rows], [1, 2, 3])               # 旧データ {"old": 1} は置き換わる
        self.assertIsNone(rows[1]["v"])
        self.assertTrue(all(isinstance(r["time"], int) for r in rows))
        self.assertNotIn("db.u", mock.tables)                               # 失敗時は本テーブルを作らない
        self.assertEqual([k for k in mock.tables if "_tmp_" in k], [])      # 一時テーブルは残さない
        self.assertEqual(mock.sessions, {})                                 # セッションも残さない
        self.assertEqual(mock.tables["db.t"]["schema"][:2], [["id", "long"], ["v", "string"]])

        mock.error_table_prefix = ""
        calls_before = len(mock.calls)
        self.assertEqual(self.run_cli(mock, "--execute"), 0)                # 再実行: t は完了済みでスキップ
        self.assertEqual(len(mock.tables["db.t"]["rows"]), 3)
        self.assertEqual(len(mock.tables["db.u"]["rows"]), 1)
        self.assertEqual(mock.calls[calls_before:].count("bulk_import/create"), 1)  # u の1回だけ

    def test_append_adds_rows(self):
        mock = MockTD()
        self.addCleanup(mock.close)
        self.assertEqual(self.run_cli(mock, "--execute", "--mode", "append"), 0)
        self.assertEqual(len(mock.tables["db.t"]["rows"]), 4)               # 既存1行 + 3行

    def test_check_auth_scheme(self):
        mock = MockTD(reject_bearer_bulk=True)
        self.addCleanup(mock.close)
        self.assertEqual(self.run_cli(mock, "--check", token="oauth-token"), 1)  # Bearer は Bulk Import で拒否
        self.assertEqual(self.run_cli(mock, "--check", token="123/abc"), 0)      # API キーは TD1 で通る
        self.assertEqual(mock.auth, {"Bearer", "TD1"})


if __name__ == "__main__":
    unittest.main()
