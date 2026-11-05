#!/usr/bin/env python3
"""Engage Studio Dashboard をビルドする（Python 標準ライブラリのみ）

集計WF（td_engage_studio_analytics.dig）の出力テーブルを tdx query で取得し、
dashboard/template.html の <script id="es-data"> にJSONとして埋め込んだHTMLを出力します。
WF内では実行しません（TD Workflow の py> は使わない方針）。Treasure Work / ローカルで実行します。

使い方:
  # TDから取得してビルド（tdx の認証済みプロファイルを使用）
  python3 dashboard/build_dashboard.py --db engage_studio_analytics --out output/engage_studio_dashboard.html

  # 取得したJSONを保存しておき、あとで再ビルド
  python3 dashboard/build_dashboard.py --db engage_studio_analytics --save-data output/data --out output/dashboard.html
  python3 dashboard/build_dashboard.py --data-dir output/data --out output/dashboard.html

  # サンプルデータ（架空）でビルド（template.html の既定データの作成用）
  python3 dashboard/build_dashboard.py --sample --out dashboard/template.html
"""
import argparse
import datetime as dt
import json
import os
import random
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
DATASETS = ["message_summary", "send_cohort", "daily", "link_clicks", "line_oa_daily"]
DATA_RE = re.compile(r'(<script type="application/json" id="es-data">)(.*?)(</script>)', re.S)


def render_sql(path, params):
    sql = open(path, encoding="utf-8").read()

    def rep(m):
        key = m.group(1).strip()
        if key not in params:
            raise SystemExit("未定義の変数 ${%s} in %s" % (key, path))
        return str(params[key])

    return re.sub(r"\$\{([^}]+)\}", rep, sql)


def run_query(sql, limit):
    with tempfile.TemporaryDirectory() as tmp:
        qf = os.path.join(tmp, "q.sql")
        of = os.path.join(tmp, "out.json")
        with open(qf, "w", encoding="utf-8") as f:
            f.write(sql)
        cmd = ["tdx", "query", "-f", qf, "--json", "--limit", str(limit), "--output", of]
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode != 0 or not os.path.exists(of):
            sys.stderr.write(res.stdout + res.stderr)
            raise SystemExit("tdx query に失敗しました")
        with open(of, encoding="utf-8") as f:
            text = f.read().strip()
        return json.loads(text) if text else []


def fetch(args):
    since = (dt.date.today() - dt.timedelta(days=args.days)).isoformat()
    params = {"output_db": args.db, "table_prefix": args.prefix, "since_date": since}
    data = {}
    for name in DATASETS:
        sql = render_sql(os.path.join(HERE, "queries", name + ".sql"), params)
        rows = run_query(sql, args.limit)
        if len(rows) >= args.limit:
            sys.stderr.write("[warn] %s が上限 %d 行に達しました。--days を短くするか --limit を増やしてください\n" % (name, args.limit))
        data[name] = rows
        print("  %-16s %6d rows" % (name, len(rows)))
    return data


def sample_data(seed=7):
    """架空のサンプルデータ（顧客名・実データを含まない）"""
    rnd = random.Random(seed)
    end = dt.date(2026, 10, 31)
    msgs, cohort, daily, links = [], [], [], []
    names = [
        ("email", "Campaign", "秋の新商品のご案内"), ("email", "Campaign", "会員限定セール 第1弾"),
        ("email", "Campaign", "会員限定セール 第2弾（リマインド）"), ("email", "Journey/Activation", "ようこそメール（新規会員）"),
        ("email", "Journey/Activation", "カート放棄リマインド"), ("email", "Journey/Activation", "購入後フォロー（7日後）"),
        ("email", "Campaign", "月刊ニュースレター 10月号"), ("email", "Campaign", "ウェビナーご招待"),
        ("line", "Campaign", "LINE限定クーポン配信"), ("line", "Journey/Activation", "LINE 誕生月メッセージ"),
    ]
    for i, (ch, model, label) in enumerate(names):
        key = "%08x-sample-%04d" % (rnd.getrandbits(32), i)
        journey = model != "Campaign"
        days = list(range(0, 45)) if journey else [rnd.randint(0, 44)]
        if label.endswith("リマインド）"):
            days = [max(0, d - 3) for d in days]
        open_base = rnd.uniform(0.28, 0.55)
        click_base = rnd.uniform(0.03, 0.12)
        total_sent = 0
        first = last = None
        for d in days:
            date = (end - dt.timedelta(days=d)).isoformat()
            sent = rnd.randint(40, 180) if journey else rnd.randint(4000, 12000)
            failed = int(sent * rnd.uniform(0.005, 0.03))
            delivered = sent - failed
            if ch == "email":
                opened = int(delivered * open_base * rnd.uniform(0.85, 1.1))
                opened_h = int(opened * rnd.uniform(0.78, 0.9))
                clicked = int(delivered * click_base * rnd.uniform(0.8, 1.2))
                clicked_h = int(clicked * rnd.uniform(0.85, 0.97))
            else:
                opened = opened_h = clicked = clicked_h = None
            cohort.append({"channel": ch, "send_date": date, "message_key": key, "message_label": label, "sent": sent,
                           "delivered": delivered, "failed": failed, "opened": opened, "opened_human": opened_h,
                           "clicked": clicked, "clicked_human": clicked_h})
            if ch == "email":
                # 開封・クリックは送信日から数日かけて減衰
                for lag, share in enumerate([0.55, 0.22, 0.1, 0.06, 0.04, 0.03]):
                    ed = (end - dt.timedelta(days=d) + dt.timedelta(days=lag))
                    if ed > end:
                        break
                    daily.append({"channel": "email", "date": ed.isoformat(), "message_key": key,
                                  "opened": int(opened * share), "opened_human": int(opened_h * share),
                                  "clicked": int(clicked * share), "clicked_human": int(clicked_h * share)})
            total_sent += sent
            first = date if first is None or date < first else first
            last = date if last is None or date > last else last
        msgs.append({"channel": ch, "message_key": key, "message_label": label, "campaign_model": model,
                     "campaign_name": label if model == "Campaign" else None, "campaign_id": key if model == "Campaign" else None,
                     "custom_event_id": key if ch == "email" else None,
                     "sender": "news@example.com" if ch == "email" else "Sample Store",
                     "first_send_date": first, "last_send_date": last, "sent": total_sent})
        if ch == "email":
            for j, path in enumerate(["/campaign/autumn", "/sale", "/members/coupon", "/stores", "/unsubscribe"]):
                uc = int(sum(r["clicked"] or 0 for r in cohort if r["message_key"] == key) * [0.5, 0.25, 0.12, 0.08, 0.05][j])
                links.append({"message_key": key, "link_url": "https://www.example.com" + path, "clicks": int(uc * 1.4),
                              "unique_clicks": uc, "unique_clicks_human": int(uc * 0.92)})
    oa = []
    for d in range(0, 45):
        date = end - dt.timedelta(days=d)
        line_sent = sum(r["sent"] for r in cohort if r["channel"] == "line" and r["send_date"] == date.isoformat())
        oa.append({"date": date.isoformat(), "status": "ready" if d >= 2 else "unready", "broadcast": rnd.choice([0, 0, 0, 3200]),
                   "targeting": 0, "api_broadcast": 0, "api_push": line_sent, "api_multicast": 0,
                   "total": line_sent + rnd.randint(5, 40)})
    for r in oa:
        r["total"] += r["broadcast"]
    return {"message_summary": msgs, "send_cohort": cohort, "daily": daily, "link_clicks": links, "line_oa_daily": oa}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--db", help="集計WFの出力DB（config/common.yml の output_db）")
    ap.add_argument("--prefix", default="es_", help="テーブル接頭辞（config/common.yml の table_prefix）")
    ap.add_argument("--days", type=int, default=400, help="取得する送信日の範囲（日）")
    ap.add_argument("--limit", type=int, default=200000, help="1クエリの最大行数")
    ap.add_argument("--data-dir", help="保存済みJSON（<dataset>.json）から読み込む")
    ap.add_argument("--save-data", help="取得したJSONを保存するフォルダ")
    ap.add_argument("--sample", action="store_true", help="架空のサンプルデータでビルド")
    ap.add_argument("--template", default=os.path.join(HERE, "template.html"))
    ap.add_argument("--source", help="画面上部に表示するデータの出所（既定: <db>.<prefix>*）")
    ap.add_argument("--out", required=True, help="出力HTML")
    args = ap.parse_args()

    if args.sample:
        data, source = sample_data(), "サンプルデータ（架空）"
    elif args.data_dir:
        data = {}
        for name in DATASETS:
            p = os.path.join(args.data_dir, name + ".json")
            data[name] = json.load(open(p, encoding="utf-8")) if os.path.exists(p) else []
        source = args.source or args.data_dir
    elif args.db:
        print("tdx query で取得中: %s.%s*" % (args.db, args.prefix))
        data = fetch(args)
        source = args.source or "%s.%s*" % (args.db, args.prefix)
    else:
        ap.error("--db / --data-dir / --sample のいずれかを指定してください")

    if args.save_data:
        os.makedirs(args.save_data, exist_ok=True)
        for name in DATASETS:
            with open(os.path.join(args.save_data, name + ".json"), "w", encoding="utf-8") as f:
                json.dump(data.get(name, []), f, ensure_ascii=False)

    jst = dt.timezone(dt.timedelta(hours=9))
    payload = dict(data)
    payload["source"] = source
    payload["generated_at"] = dt.datetime.now(jst).strftime("%Y-%m-%d %H:%M JST")
    blob = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")

    html = open(args.template, encoding="utf-8").read()
    if not DATA_RE.search(html):
        raise SystemExit("template に <script type=\"application/json\" id=\"es-data\"> がありません")
    html = DATA_RE.sub(lambda m: m.group(1) + blob + m.group(3), html, count=1)
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(html)
    print("出力: %s（%.0f KB）" % (args.out, len(html.encode("utf-8")) / 1024))


if __name__ == "__main__":
    main()
