#!/usr/bin/env python3
"""LOCAL ONLY: stdlib SQLite executes the actual rendered pipeline queries.

Ruby/Psych parses Digdag YAML; Node evaluates authored Digdag JS conditions. No
TD CLI, network, exporter or attachment code is executed. SQLite shims cover TD
clock UDFs and one explicit DATE_ADD/DATE cast rewrite; this is not TD validation.
"""
import argparse
import copy
import datetime as dt
import html
import itertools
import json
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import unittest
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
ANCHOR = int(dt.datetime(2026, 11, 5, 8, tzinfo=dt.timezone.utc).timestamp())


def yaml_load(path):
    code = """require 'json'; require 'psych'
text = File.read(ARGV.fetch(0), encoding: 'UTF-8')
ast = Psych.parse_stream(text)
check = lambda do |node|
  if node.is_a?(Psych::Nodes::Mapping)
    keys = node.children.each_slice(2).map { |pair| pair[0].value }
    raise 'duplicate YAML key' unless keys.uniq.length == keys.length
  end
  node.children&.each { |child| check.call(child) } if node.respond_to?(:children)
end
check.call(ast)
puts JSON.generate(Psych.safe_load(text, aliases: false))
"""
    return json.loads(subprocess.check_output(
        ['ruby', '-EUTF-8', '-e', code, str(path)], text=True))


def lookup(context, expression):
    value = context
    for key in expression.split('.'):
        value = value[key]
    if isinstance(value, bool):
        return 'true' if value else 'false'
    return str(value)


def render(text, config, anchor=ANCHOR, variables=None):
    context = {'config': config, 'session_unixtime': anchor, 'attempt_id': '1001', **(variables or {})}
    return re.sub(r'\$\{([^}]+)\}', lambda m: lookup(context, m[1]), text)


def evaluate(expression, config, stats=None, scope=None):
    expression = expression.removeprefix('${').removesuffix('}')
    script = """const vm=require('vm'); const fs=require('fs');
const x=JSON.parse(fs.readFileSync(0,'utf8'));
process.stdout.write(JSON.stringify(vm.runInNewContext(x.expr,
  Object.assign({config:x.config,td:{last_results:x.stats}},x.scope), {timeout:1000})));"""
    payload = {'expr': expression, 'config': config, 'scope': scope or {}, 'stats': stats or {
        'recipient_count': 0, 'unique_email_count': 0, 'execution_lag_seconds': 0}}
    return json.loads(subprocess.check_output(['node', '-e', script],
        input=json.dumps(payload), text=True))


def planned_tasks(config, stats=None, entry='cart_abandonment.dig'):
    tasks = []
    def walk(node, scope):
        if 'if>' in node:
            branch = '_do' if evaluate(node['if>'], config, stats, scope) else '_else_do'
            if branch in node:
                walk(node[branch], scope)
            return
        if 'fail>' in node:
            raise ValueError(node['fail>'])
        if 'for_each>' in node:
            axes = node['for_each>']
            values = [evaluate(v, config, stats, scope) if isinstance(v, str) else v for v in axes.values()]
            for combination in itertools.product(*values):
                walk(node['_do'], {**scope, **dict(zip(axes, combination))})
            return
        if 'td>' in node:
            tasks.append({**node, '_scope': scope})
        for key, child in node.items():
            if key.startswith('+'):
                walk(child, scope)
    walk(yaml_load(ROOT / entry), {})
    return tasks


class Pipeline:
    def __init__(self, mode='both', anchor=ANCHOR):
        self.config = copy.deepcopy(yaml_load(ROOT / 'config/params.yml'))
        self.config['mode'] = mode
        self.anchor = anchor
        self.attempt_id = '1001'
        self.db = sqlite3.connect(':memory:')
        self.db.row_factory = sqlite3.Row
        self.db.create_function('TD_TIME_FORMAT', 3, self.time_format)
        self.db.create_function('TD_TIME_PARSE', 2, self.time_parse)
        self.db.create_function('LEAST', -1, min)
        self.db.create_function('TO_UNIXTIME', 1, self.to_unix)
        self.wall_offset = 0
        self.db.create_function('current_timestamp', 0, lambda: dt.datetime.fromtimestamp(
            self.anchor + self.wall_offset, dt.timezone.utc).strftime('%Y-%m-%d %H:%M:%S'))
        self.db.executescript(self.sql('adapters/canonical_schema.sql'))
        self.counter = 0

    @staticmethod
    def time_format(epoch, fmt, timezone):
        assert fmt == 'yyyy-MM-dd', fmt
        return dt.datetime.fromtimestamp(epoch, ZoneInfo(timezone)).strftime('%Y-%m-%d')

    @staticmethod
    def time_parse(value, timezone):
        return int(dt.datetime.fromisoformat(value).replace(tzinfo=ZoneInfo(timezone)).timestamp())

    @staticmethod
    def to_unix(value):
        return int(dt.datetime.fromisoformat(value).replace(tzinfo=dt.timezone.utc).timestamp())

    def sql(self, name, variables=None):
        text = render((ROOT / name).read_text(), self.config, self.anchor,
                      {'attempt_id': self.attempt_id, **(variables or {})})
        # Explicit local portability shim for Trino date arithmetic, not broad SQL transpilation.
        text = re.sub(r"CAST\(DATE_ADD\('day', -1, CAST\((TD_TIME_FORMAT\([^)]*\)) AS DATE\)\) AS VARCHAR\)",
                      r"DATE(\1, '-1 day')", text)
        return text.replace('abandonment_input.', 'abandonment_input__').replace(
            'abandonment_work.', 'abandonment_work__')

    def table(self, key):
        return self.config['sources'][key].replace('.', '__')

    def insert(self, table, **row):
        keys = ','.join('"' + k + '"' for k in row)
        placeholders = ','.join('?' for _ in row)
        self.db.execute(f'INSERT INTO {self.table(table)} ({keys}) VALUES ({placeholders})', list(row.values()))

    def contact(self, member, *, email=None, consent=True, suppressed=False, at=None, row_id=None):
        self.counter += 1
        self.insert('recipients', member_id=member, email=email or f'{member}@example.invalid',
                    consent=consent, suppressed=suppressed, updated_at=at or self.anchor-100,
                    row_id=row_id or f'{self.counter:08d}')

    def identity(self, device, member, at=None, row_id='1'):
        self.insert('identities', device_id=device, member_id=member,
                    updated_at=at or self.anchor-100, row_id=row_id)

    def event(self, member, kind='product_view', *, age=5000, at=None, device=None,
              product='p1', event_id=None, quantity=1, position=1, name='Example item', url=None):
        self.counter += 1
        self.insert('events', time=at if at is not None else self.anchor-age,
                    event_id=event_id or f'e{self.counter:08d}', device_id=device if device is not None else f'd-{member}',
                    member_id=member, event_type=kind, product_id=product, quantity=quantity,
                    item_position=position, item_name=name, item_url=url or f'https://example.invalid/products/{product}',
                    image_url=f'https://example.invalid/images/{product}', brand='Example brand', price=12.5, original_price=15.0)

    def product(self, product, *, available=True, published=True, low_stock=False, at=None, row_id='1'):
        self.insert('products', product_id=product, updated_at=at or self.anchor-100, row_id=row_id,
                    item_name=f'Master {product}', item_url=f'https://example.invalid/products/{product}',
                    image_url=f'https://example.invalid/images/{product}', brand='Master brand', price=10.0,
                    original_price=20.0, available=available, published=published, low_stock=low_stock)

    def history(self, member, kind, *, age=1000, decision='old', status='reserved'):
        self.insert('history', member_id=member, kind=kind, decision_id=decision, time=self.anchor-age, status=status)

    def build(self):
        self.db.execute(self.sql('queries/ensure_history.sql'))
        steps = [('events', 'queries/events.sql'), ('candidates', 'queries/candidates.sql')]
        for name in ('products', 'recommendations', 'attributes', 'coupons'):
            source = 'load' if self.config['personalization'][name] else 'empty'
            steps.append((name, f'queries/{source}/{name}.sql'))
        steps += [('items', 'queries/items.sql'), ('send_list', 'queries/send_list.sql')]
        for name, query in steps:
            table = f'abandonment_work__abandonment_{name}'
            self.db.execute(f'DROP TABLE IF EXISTS {table}')
            self.db.execute(f'CREATE TABLE {table} AS {self.sql(query)}')
        return [dict(r) for r in self.db.execute('SELECT * FROM abandonment_work__abandonment_send_list ORDER BY member_id')]

    def reserve(self):
        self.db.execute(f'INSERT INTO {self.table("history")} {self.sql("queries/reserve.sql")}')

    def export(self, kind):
        return [dict(r) for r in self.db.execute(self.sql(f'queries/export_{kind}.sql'))]


def delivery_payload(row):
    return {key: value for key, value in row.items() if key not in ('member_id','run_time','decision_id')}


def preview(row):
    """Minimal local output-contract preview, NOT an Engage/Liquid renderer."""
    out = [f'<article data-kind="{html.escape(row["kind"])}" data-variant="{html.escape(row["variant"])}">']
    for i in range(1, 5):
        if row[f'item_{i}_product_id']:
            out.append(f'<a href="{html.escape(row[f"item_{i}_item_url"], quote=True)}">'
                       f'{html.escape(row[f"item_{i}_item_name"])}</a>')
    if row['coupon_code']:
        out.append(f'<p>{html.escape(row["coupon_description"])}</p>')
    return ''.join(out) + '</article>'


class SmokeTests(unittest.TestCase):
    def test_all_modes_and_cart_priority(self):
        for mode, expected in [('cart', {'c':'cart'}), ('browser', {'b':'browser'}), ('both', {'b':'browser','c':'cart'})]:
            with self.subTest(mode=mode):
                p = Pipeline(mode)
                p.contact('b'); p.event('b')
                p.contact('c'); p.event('c', 'product_view', age=5100)
                p.event('c', 'cart_item', age=5000, device='second-device')
                self.assertEqual({r['member_id']:r['kind'] for r in p.build()}, expected)

    def test_disabled_workflow_has_no_td_tasks(self):
        p = Pipeline()
        self.assertEqual(planned_tasks(p.config), [])
        for path in ROOT.glob('*.dig'):
            parsed = yaml_load(path)
            self.assertNotIn('schedule', parsed)
        self.assertEqual(yaml_load(ROOT/'config/params.yml'), yaml_load(ROOT/'config/params.example.yml'))
        self.assertFalse(p.config['delivery']['enabled'])
        self.assertFalse(p.config['delivery']['approved'])

    def test_templates_and_yaml_are_resolved_in_all_modes(self):
        for mode in ('cart','browser','both'):
            p = Pipeline(mode); p.config['workflow']['enabled'] = True
            for enabled in (False, True):
                for key in p.config['personalization']:
                    if key != 'max_items': p.config['personalization'][key] = enabled
                for task in planned_tasks(p.config):
                    sql = render((ROOT/task['td>']).read_text(), p.config)
                    self.assertNotIn('${', sql)
                    self.assertEqual(task['engine'], 'presto')
                    self.assertNotIn('result_connection', task)
                p.contact(f'{mode}-{enabled}'); p.event(f'{mode}-{enabled}', 'cart_item' if mode=='cart' else 'product_view')
                p.build()  # syntax + SQL name resolution for every selected query

    def test_browser_delivery_needs_no_cart_campaign_or_outputs(self):
        p = Pipeline('browser'); p.config['workflow']['enabled'] = True
        p.config['delivery'].update(enabled=True, approved=True, connection='example_connection', workspace_id='example_workspace', browser_campaign_id='example_campaign')
        del p.config['delivery']['cart_campaign_id']
        tasks = planned_tasks(p.config, dict(recipient_count=1, unique_email_count=1, execution_lag_seconds=0))
        self.assertNotIn('queries/export_cart.sql', [t['td>'] for t in tasks])
        self.assertIn('queries/export_browser.sql', [t['td>'] for t in tasks])
        p.contact('b'); p.event('b'); self.assertEqual(len(p.build()), 1)
        self.assertEqual(p.export('cart'), [])


class FixtureTests(unittest.TestCase):
    def test_recent_activity_and_latest_session_guard(self):
        p=Pipeline('browser'); p.contact('m'); p.event('m', age=6000)
        p.event('m','activity',age=100,device='another-device',product=None)
        self.assertEqual(p.build(), [])
        # A later inactive session with no PDP must not resurrect an older PDP session.
        q=Pipeline('browser'); q.contact('m'); q.event('m',age=20000)
        q.event('m','activity',age=5000,product=None)
        self.assertEqual(q.build(), [])

    def test_rolling_half_open_boundaries(self):
        p=Pipeline('browser')
        for member, age in [('start',86400),('inside',2401),('end',2400),('old',86401)]:
            p.contact(member); p.event(member,age=age)
        self.assertEqual({r['member_id'] for r in p.build()}, {'start','inside'})

    def test_overnight_window_and_recent_guard(self):
        p=Pipeline('browser'); p.config['window']['kind']='overnight'
        for member, when in [('start','2026-11-04 21:00:00'),('midnight','2026-11-05 00:00:00'),('end','2026-11-05 07:00:00'),('before','2026-11-04 20:59:59')]:
            p.contact(member); p.event(member,at=p.time_parse(when,'UTC'))
        self.assertEqual({r['member_id'] for r in p.build()}, {'start','midnight'})
        p.event('midnight','activity',age=1,product=None)
        self.assertEqual({r['member_id'] for r in p.build()}, {'start'})

    def test_dst_overnight_uses_local_calendar_date(self):
        anchor=Pipeline.time_parse('2026-11-01 08:00:00','America/New_York')
        p=Pipeline('browser',anchor); p.config['window']['kind']='overnight'; p.config['timezone']='America/New_York'
        start=p.time_parse('2026-10-31 21:00:00','America/New_York')
        end=p.time_parse('2026-11-01 07:00:00','America/New_York')
        self.assertEqual(end-start,11*3600)
        p.contact('m'); p.event('m',at=start)
        self.assertEqual(len(p.build()),1)

    def test_purchase_web_and_order_cross_device(self):
        for purchase in ('web-after','web-before-same-session','order','cancelled-order'):
            with self.subTest(purchase=purchase):
                p=Pipeline('both'); p.contact('m'); p.event('m','cart_item',age=5000)
                if purchase=='web-after': p.event('m','purchase',age=4900,device='other',product=None)
                elif purchase=='web-before-same-session':
                    p.config['suppression']['purchase_seconds']=0
                    p.event('m','purchase',age=5100,product=None)
                else: p.insert('orders',time=p.anchor-4900,member_id='m',order_id='o',product_id='p1',cancelled=purchase=='cancelled-order')
                self.assertEqual(len(p.build()),1 if purchase=='cancelled-order' else 0)

    def test_shared_cart_exclusion_in_browser_only(self):
        for age, expected in [(5100,0),(4000,0),(172801,1)]:
            p=Pipeline('browser'); p.contact('m'); p.event('m',age=5000)
            p.event('m','cart_item',age=age,device='other')
            self.assertEqual(len(p.build()),expected)

    def test_identity_cross_device_and_ambiguity(self):
        p=Pipeline('browser'); p.contact('member'); p.identity('cookie','member')
        p.event(None,device='cookie'); self.assertEqual(p.build()[0]['member_id'],'member')
        p.identity('cookie','another-member',at=p.anchor-50,row_id='2')
        self.assertEqual(p.build(), [])
        q=Pipeline('browser'); q.contact('member'); q.event('member',device='')
        q.event(None,device='anonymous'); self.assertEqual(q.build(), [])
        r=Pipeline('browser'); r.contact('member'); r.identity('cookie','member')
        r.event(None,device='cookie'); r.event('member','purchase',age=4900,device='other',product=None)
        self.assertEqual(r.build(), [])

    def test_shared_device_explicit_members_fail_closed_across_devices(self):
        p=Pipeline('browser')
        for member in ('one','two'):
            p.contact(member); p.event(member,device='shared')
            p.event(member,age=4900,device=f'other-{member}')
        self.assertEqual(p.build(), [])
        q=Pipeline('browser'); q.contact('one'); q.event('one',device='personal')
        q.identity('known-shared','one',row_id='a'); q.identity('known-shared','two',row_id='b')
        self.assertEqual(q.build(), [])

    def test_latest_invalid_product_does_not_revive_old_browser_item(self):
        for invalid in ('null-id','blank-id','unsafe-url'):
            p=Pipeline('browser'); p.contact('m'); p.event('m',age=5100,product='valid')
            kwargs={'product':None} if invalid=='null-id' else {'product':''} if invalid=='blank-id' else {'product':'new','url':'http://example.invalid/unsafe'}
            p.event('m',age=5000,**kwargs)
            with self.subTest(invalid=invalid): self.assertEqual(p.build(), [])

    def test_latest_consent_ties_future_and_shared_email(self):
        p=Pipeline('browser'); p.event('m'); p.contact('m',at=p.anchor-300,row_id='a')
        p.contact('m',consent=False,at=p.anchor-100,row_id='b')
        p.contact('m',consent=True,at=p.anchor+100,row_id='c')
        self.assertEqual(p.build(), [])
        q=Pipeline('browser'); q.event('m'); q.contact('m',row_id='a'); q.contact('m',consent=False,row_id='z')
        self.assertEqual(q.build(), [])
        r=Pipeline('both')
        for m in ('a','b'): r.event(m); r.contact(m,email='shared@example.invalid')
        self.assertEqual(r.build(), [])
        s=Pipeline('browser'); s.event('m'); s.contact('m',consent=None)
        self.assertEqual(s.build(), [])

    def test_latest_product_and_latest_browser_item(self):
        p=Pipeline('browser'); p.config['personalization']['products']=True
        p.contact('m'); p.event('m',age=5100,product='old'); p.event('m',age=5000,product='new')
        p.product('old'); p.product('new',at=p.anchor-200,row_id='a')
        p.product('new',available=False,at=p.anchor-100,row_id='b')
        self.assertEqual(p.build(), [])
        p.product('new',published=False,at=p.anchor-50,row_id='c'); self.assertEqual(p.build(), [])
        p.product('new',low_stock=True,at=p.anchor-25,row_id='d')
        row=p.build()[0]
        self.assertEqual((row['item_1_product_id'],row['variant']),('new','low_stock'))
        self.assertEqual(row['item_2_product_id'],'')

    def test_cart_snapshot_clear_quantity_and_four_slots(self):
        p=Pipeline('cart'); p.contact('m')
        p.event('m','cart_item',age=5100,product='removed')
        for i in range(1,7): p.event('m','cart_item',event_id='snapshot',product=f'p{i}',position=i)
        p.event('m','cart_item',event_id='snapshot',product='zero',position=0,quantity=0)
        row=p.build()[0]
        self.assertEqual([row[f'item_{i}_product_id'] for i in range(1,5)],['p1','p2','p3','p4'])
        p.config['personalization']['max_items']=2
        row=p.build()[0]; self.assertEqual(row['item_3_product_id'],'')
        p.event('m','cart_clear',age=4900,product=None)
        self.assertEqual(p.build(), [])

    def test_shared_frequency_and_distinct_reservations(self):
        for mode in ('cart','browser'):
            p=Pipeline(mode); p.contact('m'); p.event('m','cart_item' if mode=='cart' else 'product_view')
            p.history('m',mode); self.assertEqual(p.build(), [])
            q=Pipeline(mode); q.contact('m'); q.event('m','cart_item' if mode=='cart' else 'product_view')
            other='browser' if mode=='cart' else 'cart'
            q.history('m',other,decision='one'); q.history('m',other,decision='one')
            self.assertEqual(len(q.build()),1)
            q.history('m',other,decision='two'); self.assertEqual(q.build(), [])

    def test_cap_boundary_and_calendar_day(self):
        p=Pipeline('browser'); p.contact('m'); p.event('m'); p.history('m','browser',age=86400)
        self.assertEqual(p.build(), [])
        q=Pipeline('browser'); q.contact('m'); q.event('m'); q.history('m','browser',age=86401)
        self.assertEqual(len(q.build()),1)
        q.config['frequency']['period']='calendar_day'; q.config['timezone']='Asia/Tokyo'
        # 08:00 UTC is 17:00 JST; before JST midnight is out of this calendar day.
        q.db.execute(f'DELETE FROM {q.table("history")}')
        midnight=q.time_parse('2026-11-05 00:00:00','Asia/Tokyo')
        q.history('m','browser',age=q.anchor-midnight+1)
        self.assertEqual(len(q.build()),1)
        q.history('m','browser',age=q.anchor-midnight,decision='boundary')
        self.assertEqual(q.build(), [])

    def test_optional_sources_are_not_required_when_disabled(self):
        p=Pipeline('browser'); p.contact('m'); p.event('m')
        for key in ('products','recommendations','attributes','coupons'):
            p.db.execute(f'DROP TABLE {p.table(key)}')
        self.assertEqual(len(p.build()),1)

    def test_reservation_exact_payload_idempotence_and_retry_suppression(self):
        p=Pipeline('both')
        for m,k in [('c','cart_item'),('b','product_view')]: p.contact(m); p.event(m,k)
        rows=p.build(); self.assertEqual(p.db.execute(f'SELECT COUNT(*) FROM {p.table("history")}').fetchone()[0],0)
        p.reserve(); p.reserve()
        ledger={r['decision_id'] for r in p.db.execute(f'SELECT * FROM {p.table("history")}')}
        exported=p.export('cart')+p.export('browser')
        self.assertEqual({(r['email'],r['kind']) for r in exported},{(r['email'],r['kind']) for r in rows})
        self.assertEqual({r['decision_id'] for r in rows},ledger)
        self.assertTrue(all('member_id' not in r and 'run_time' not in r and 'decision_id' not in r for r in exported))
        self.assertEqual(len(ledger),2); self.assertEqual(p.build(), [])

    def test_enrichment_latest_rows_coupon_expiry_and_rendering(self):
        p=Pipeline('cart'); p.contact('m'); p.event('m','cart_item',name='<unsafe & name>')
        p.config['personalization'].update(recommendations=True,attributes=True,coupons=True)
        for product, pos in [('p1',1),('r1',2),('r2',3)]:
            p.insert('recommendations',member_id='m',snapshot_at=p.anchor-100,updated_at=p.anchor-100,
                row_id=product,product_id=product,position=pos,item_name=product,
                item_url=f'https://example.invalid/{product}',image_url='',brand='',price=5,original_price=6,available=True)
        p.insert('attributes',member_id='m',row_id='a',updated_at=p.anchor-200,points=1,segment='old')
        p.insert('attributes',member_id='m',row_id='b',updated_at=p.anchor-100,points=2,segment='new')
        p.insert('coupons',member_id='m',row_id='a',updated_at=p.anchor-200,code='EXAMPLE',
                 description='Example offer',image_url='',valid_from=p.anchor-1000,valid_until=p.anchor+1,active=True)
        row=p.build()[0]
        self.assertEqual((row['recommend_1_product_id'],row['recommend_2_product_id']),('r1','r2'))
        self.assertEqual((row['segment'],row['coupon_code']),('new','EXAMPLE'))
        self.assertIn('&lt;unsafe &amp; name&gt;',preview(row)); self.assertNotIn('<unsafe',preview(row))
        p.insert('coupons',member_id='m',row_id='b',updated_at=p.anchor-100,code='EXPIRED',
                 description='Expired',image_url='',valid_from=p.anchor-1000,valid_until=p.anchor,active=True)
        row=p.build()[0]; self.assertEqual(row['coupon_code'],'')
        # A complete empty/new recommendation snapshot must not revive old products.
        p.insert('recommendations',member_id='m',snapshot_at=p.anchor-50,updated_at=p.anchor-50,
                 row_id='empty',product_id=None,available=False)
        self.assertEqual(p.build()[0]['recommend_1_product_id'],'')
        self.assertTrue(all(value is not None for value in row.values()))


class FullTests(unittest.TestCase):
    def test_strict_boolean_and_numeric_types_before_any_td(self):
        boolean_paths=[('workflow','enabled'),('delivery','enabled'),('delivery','approved'),
            ('personalization','products'),('personalization','recommendations'),
            ('personalization','attributes'),('personalization','coupons'),('testing','enabled'),('testing','approved')]
        for entry in ('cart_abandonment.dig','send_email_test.dig'):
            for section,key in boolean_paths:
                for value in ('false','true',0,1,None):
                    p=Pipeline(); p.config[section][key]=value
                    with self.subTest(entry=entry,path=(section,key),value=value),self.assertRaises(ValueError):
                        planned_tasks(p.config,entry=entry)
            for value in ('100',1.5,-1,True):
                p=Pipeline(); p.config['workflow']['max_recipients']=value
                with self.subTest(entry=entry,numeric=value),self.assertRaises(ValueError):
                    planned_tasks(p.config,entry=entry)

    def test_stable_signal_key_prior_reservation_and_attempt_binding(self):
        p=Pipeline('browser'); p.contact('m'); p.event('m')
        p.config['frequency'].update(per_kind=3,total=5,window_seconds=1)
        row=p.build()[0]; p.reserve()
        self.assertEqual(p.export('browser'),[delivery_payload(row)])
        p.attempt_id='1002'; p.reserve()  # existing signal is NOT a new-attempt reservation
        self.assertEqual(p.export('browser'),[])
        check=dict(p.db.execute(p.sql('queries/check_reservations.sql')).fetchone())
        self.assertEqual(check['existing_decision_count'],1)
        p.config['workflow']['enabled']=True
        p.config['delivery'].update(enabled=True,approved=True,connection='example',workspace_id='example',browser_campaign_id='example')
        with self.assertRaises(ValueError):
            planned_tasks(p.config,dict(recipient_count=1,unique_email_count=1,execution_lag_seconds=0,existing_decision_count=1))
        p.anchor+=120
        self.assertEqual(p.build(),[])  # same signal, outside cap window, still blocked
        self.assertEqual(p.db.execute(f'SELECT COUNT(*) FROM {p.table("history")}').fetchone()[0],1)

    def test_future_reservation_and_same_second_cart_clear(self):
        p=Pipeline('browser'); p.contact('m'); p.event('m')
        p.history('m','browser',age=-300)
        self.assertEqual(p.build(),[])  # later attempt already consumed this cap
        q=Pipeline('cart'); q.contact('m')
        q.event('m','cart_item',event_id='z-last-lexically')
        q.event('m','cart_clear',product=None,event_id='a-first-lexically')
        self.assertEqual(q.build(),[])  # deletion wins a timestamp tie

    def test_invalid_latest_consent_and_normalized_email_fail_closed(self):
        for invalid in ('null-time','null-id','blank-id','conflict'):
            p=Pipeline('browser'); p.contact('m'); p.event('m')
            row={'member_id':'m','email':'m@example.invalid','consent':False,'suppressed':False,
                 'updated_at':p.anchor-100,'row_id':'bad'}
            if invalid=='null-time': row['updated_at']=None
            elif invalid=='null-id': row['row_id']=None
            elif invalid=='blank-id': row['row_id']=''
            else: row['row_id']='00000001'  # same key as the grant, conflicting consent
            p.insert('recipients',**row)
            with self.subTest(invalid=invalid): self.assertEqual(p.build(),[])
        q=Pipeline('browser')
        q.contact('a',email=' Shared@Example.Invalid '); q.event('a')
        q.contact('b',email='shared@example.invalid'); q.event('b')
        self.assertEqual(q.build(),[])
        r=Pipeline('browser'); r.contact('m',email=' M@Example.Invalid '); r.event('m')
        row=r.build()[0]; self.assertEqual(row['email'],'m@example.invalid'); r.reserve()
        self.assertEqual(r.export('browser'),[delivery_payload(row)])
        r.insert('recipients',member_id='m',email='m@example.invalid',consent=False,
                 suppressed=False,updated_at=None,row_id='broken-opt-out')
        self.assertEqual(r.export('browser'),[])

    @staticmethod
    def enable_test(p, mode='smoke', recipients=None):
        recipients=recipients or ['render@example.invalid']
        p.config['testing'].update(enabled=True,approved=True,mode=mode,recipients=recipients,
            allowlist=recipients,expected_messages=len(recipients)*(2 if p.config['mode']=='both' else 1)*{'smoke':1,'fixture':2,'full':3}[mode],
            max_messages=20,connection='synthetic_connection',workspace_id='synthetic_workspace',
            cart_campaign_id='synthetic_cart',browser_campaign_id='synthetic_browser')

    def test_synthetic_test_gates_and_message_counts(self):
        p=Pipeline(); self.assertEqual(planned_tasks(p.config,entry='send_email_test.dig'),[])
        for bad in ('approval','allowlist','duplicates','count','limit','production-campaign','production-workspace','sql-email'):
            q=Pipeline(); self.enable_test(q)
            if bad=='approval': q.config['testing']['approved']=False
            elif bad=='allowlist': q.config['testing']['allowlist']=[]
            elif bad=='duplicates': q.config['testing']['recipients']*=2
            elif bad=='count': q.config['testing']['expected_messages']=1
            elif bad=='limit': q.config['testing']['max_messages']=1
            elif bad=='production-campaign': q.config['delivery']['cart_campaign_id']='synthetic_cart'
            elif bad=='production-workspace': q.config['delivery']['workspace_id']='synthetic_workspace'
            else: q.config['testing']['recipients']=["bad'@example.invalid"]
            with self.subTest(bad=bad),self.assertRaises(ValueError): planned_tasks(q.config,entry='send_email_test.dig')

    def test_synthetic_payload_shape_forced_destination_and_selected_mode(self):
        for mode in ('cart','browser','both'):
            for test_mode,variant_count in [('smoke',1),('fixture',2),('full',3)]:
                p=Pipeline(mode); self.enable_test(p,test_mode,['render@example.invalid','second@example.invalid'])
                for feature in ('recommendations','attributes','coupons'): p.config['personalization'][feature]=True
                tasks=planned_tasks(p.config,entry='send_email_test.dig')
                self.assertEqual(len(tasks),2*(2 if mode=='both' else 1)*variant_count)
                # Build one real LOCAL fixture solely to compare its output contract.
                p.contact('m'); p.event('m','cart_item' if mode=='cart' else 'product_view')
                columns=set(delivery_payload(p.build()[0]))
                for task in tasks:
                    scope=task['_scope']
                    row=dict(p.db.execute(p.sql(task['td>'],scope)).fetchone())
                    self.assertEqual(set(row),columns)
                    self.assertEqual(row['email'],scope['test_recipient'])
                    self.assertIn(row['email'],p.config['testing']['allowlist'])
                    self.assertEqual(row['kind'],scope['test_kind'])
                    self.assertNotIn(' FROM ',p.sql(task['td>'],scope).upper())
                    self.assertEqual(task['job_retry'],0)
                    campaign=evaluate(task['result_settings']['always_on_campaign_id'],p.config,scope=scope)
                    self.assertEqual(campaign,p.config['testing'][row['kind']+'_campaign_id'])
                    self.assertTrue(all(value is not None for value in row.values()))
                    if scope['test_variant']=='minimal': self.assertEqual(row['recommend_1_product_id'],'')
                    else: self.assertTrue(row['recommend_1_product_id'])

    def test_export_current_consent_lag_and_empty_payload_guards(self):
        for kind in ('cart', 'browser'):
            p=Pipeline(kind); p.contact('m'); p.event('m','cart_item' if kind=='cart' else 'product_view')
            row=p.build()[0]
            self.assertEqual(p.export(kind), [])  # reservation is mandatory
            p.reserve(); self.assertEqual(p.export(kind), [delivery_payload(row)])
            p.wall_offset=901; self.assertEqual(p.export(kind), [])
            p.wall_offset=-1; self.assertEqual(p.export(kind), [])
            p.wall_offset=50
            p.contact('m',consent=False,at=p.anchor+25,row_id='new-opt-out')
            self.assertEqual(p.export(kind), [])  # not the old as-of consent
            self.assertEqual(p.db.execute(f'SELECT COUNT(*) FROM {p.table("history")}').fetchone()[0],1)
        p=Pipeline(); p.config['workflow']['enabled']=True
        p.config['delivery'].update(enabled=True,approved=True,connection='x',workspace_id='x',cart_campaign_id='c',browser_campaign_id='b')
        paths=[t['td>'] for t in planned_tasks(p.config)]
        self.assertNotIn('queries/reserve.sql',paths)  # zero recipients means no export
        self.assertNotIn('queries/export_cart.sql',paths)

    def test_identifier_and_overnight_config_guards(self):
        for change in ('source','prefix','negative','fraction','time','daytime'):
            p=Pipeline(); p.config['workflow']['enabled']=True
            if change=='source': p.config['sources']['events']='unsafe; DROP TABLE x'
            elif change=='prefix': p.config['output']['prefix']='bad-name'
            elif change=='negative': p.config['suppression']['cart_seconds']=-1
            elif change=='fraction': p.config['frequency']['per_kind']=1.5
            else:
                p.config['window']['kind']='overnight'
                p.config['window']['overnight_start']='29:00:00' if change=='time' else '06:00:00'
            with self.subTest(change=change), self.assertRaises(ValueError): planned_tasks(p.config)

    def test_delivery_guards_breaker_lag_and_config(self):
        p=Pipeline('both'); p.config['workflow']['enabled']=True
        for bad in ('mode','inactivity','scan','items'):
            q=copy.deepcopy(p.config)
            if bad=='mode': q['mode']='invalid'
            elif bad=='inactivity': q['window']['inactivity_seconds']=1
            elif bad=='scan': q['scan']['lookback_seconds']=1
            else: q['personalization']['max_items']=5
            with self.assertRaises(ValueError): planned_tasks(q)
        with self.assertRaises(ValueError):
            planned_tasks(p.config,dict(recipient_count=101,unique_email_count=101,execution_lag_seconds=0))
        p.config['delivery'].update(enabled=True,approved=True,connection='example',workspace_id='example',cart_campaign_id='cart',browser_campaign_id='browser')
        for lag in (-1,901):
            with self.assertRaises(ValueError): planned_tasks(p.config,dict(recipient_count=1,unique_email_count=1,execution_lag_seconds=lag))
        p.config['delivery']['approved']=False
        with self.assertRaises(ValueError): planned_tasks(p.config)

    def test_all_template_variables_and_safe_operators(self):
        p=Pipeline()
        for path in list((ROOT/'queries').rglob('*.sql'))+list((ROOT/'adapters').rglob('*.sql')):
            scope={'test_recipient':'render@example.invalid','test_kind':'cart','test_variant':'normal'}
            self.assertNotIn('${',render(path.read_text(),p.config,variables=scope),str(path))
        for path in ROOT.glob('*.dig'):
            text=path.read_text(); yaml_load(path)
            for forbidden in ('sh>:', 'http>:', 'mail>:', 'call>:'):
                self.assertNotIn(forbidden,text)
            self.assertNotRegex(text,r'(?m)^\s*_retry:')
            for line in text.splitlines():
                if line.lstrip().startswith('job_retry:'):
                    self.assertEqual(line.strip(),'job_retry: 0')
        core=(ROOT/'cart_abandonment.dig').read_text()
        self.assertEqual(core.count('!include : config/params.yml'),1)
        self.assertLess(core.index('+reserve:'),core.index('+cart:'))
        self.assertNotIn('profile:',core)

    def test_output_contract_and_payload_checks_sql(self):
        p=Pipeline('browser'); p.contact('m'); p.event('m')
        row=p.build()[0]
        for n in range(1,5):
            for field in ('product_id','item_name','item_url','image_url','brand','price','original_price'):
                self.assertIn(f'item_{n}_{field}',row)
                self.assertIn(f'recommend_{n}_{field}',row)
        check=dict(p.db.execute(p.sql('queries/check_payload.sql')).fetchone())
        self.assertEqual((check['recipient_count'],check['unique_email_count']),(1,1))
        self.assertTrue(row['decision_id'].startswith('1:m:browser:'))
        self.assertEqual(p.export('browser'), [])  # a prebuilt list alone cannot export
        p.reserve()
        self.assertEqual(p.export('browser'),[delivery_payload(row)])


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode',choices=('smoke','fixture','full'),help='LOCAL test selection only; default config.testing.mode')
    args=parser.parse_args()
    mode=args.mode or yaml_load(ROOT/'config/params.yml')['testing']['mode']
    classes=[SmokeTests]
    if mode in ('fixture','full'): classes.append(FixtureTests)
    if mode=='full': classes.append(FullTests)
    suite=unittest.TestSuite(unittest.defaultTestLoader.loadTestsFromTestCase(c) for c in classes)
    result=unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__=='__main__':
    sys.exit(main())
