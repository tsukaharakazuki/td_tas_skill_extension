---
name: cart-abandonment-workflow
description: Use when the user wants to create, customize, generalize, validate, or deploy a Treasure Data cart-abandonment email workflow. Covers customer-agnostic Digdag workflow construction, Web log source and cart/purchase logic interviews, Engage Studio Always-On Campaign integration, external connector mappings, recommendation/points/coupon options, dummy-data test email delivery, and workflow validation. Trigger on カート放棄, カート離脱, abandoned cart, cart abandonment, cart-abandonment workflow, or requests to reuse the cart-abandonment sample for another customer.
---

# Cart-Abandonment Workflow Builder

Build a reusable Treasure Data Workflow (Digdag) for cart-abandonment email delivery. Treat the included workflow sample as a reference implementation, not as a customer configuration. Never carry customer, brand, account, campaign, URL, coupon, recipient, or internal table identifiers into a new customer's workflow.

## Package Layout

Keep the implementation split into two locations:

```text
.claude/skills/cart-abandonment-workflow/
└── SKILL.md                         # this orchestration and interview guide

cart-abandonment-workflow/cart-abandonment/
├── README.md                        # sample scope and customization map
├── config/params.example.yml        # placeholders and customer inputs
├── *.dig                            # workflow and test entry points
├── queries/                         # SQL templates
└── tdx.json                         # generic local project metadata
```

Use the sample under `cart-abandonment-workflow/cart-abandonment/` as the starting point. Keep customer-specific values in a customer-owned copy of `config/params.yml` or in workflow exports; do not put real credentials or API keys in the sample.

## Operating Rules

1. Load the `workflow-skills:digdag` skill before editing or deploying `.dig` files.
2. Use Trino/Presto SQL conventions appropriate to the project. Prefer `tdx wf validate` for syntax/configuration checks.
3. Do not run a live workflow or send a real campaign until the user explicitly confirms the scope and destination. For `tdx wf run`, preview with `--dry-run` first and explain external sends.
4. Treat test email delivery as an external side effect. Confirm the exact test recipient(s), expected message count, and campaign before running it.
5. Do not invent source columns, table names, consent rules, campaign IDs, connector fields, or cart semantics. Ask, inspect, or mark them as unresolved placeholders.
6. Preserve privacy: use hashed identifiers for joins where appropriate, query only opted-in recipients, and exclude staff/test accounts through configuration.
7. Keep the sample customer-agnostic. Avoid customer-specific brand names, account IDs, internal email addresses, customer domains, and customer-specific campaign or template IDs.

## Build Process

### 1. Establish the delivery route

Ask which route applies:

- **Engage Studio Always-On Campaign**: retain the basic pattern of creating a send-list table and using a `td>` result export with `treasure_engage_v1`. Obtain the already-planned Always-On Campaign information before writing the final workflow.
- **External connector**: identify connector type, destination object/list/campaign, authentication/connection name, required columns, consent/opt-out fields, and connector-specific transformations. Write SQL to produce exactly the connector's required schema.

For Engage Studio, collect at minimum:

- Engage connection name
- workspace ID
- Always-On Campaign ID(s), including separate normal/low-stock campaigns if applicable
- template/event identifier(s), if used for history or branching
- expected input column names and Liquid variables
- whether one template handles all variants or separate campaigns/templates are used

If no campaign exists, stop short of live-send configuration and produce a clearly marked placeholder plus a campaign-input checklist.

### 2. Inspect the customer's data model

Ask for or inspect the following before writing cart SQL:

- Real-time Web log database and table
- event timestamp column and timezone
- cookie/visitor identifiers and fallback order
- stable user identifier (hashed email, email, member ID, or other key)
- URL/path column and the cart-page rule
- item payload format: one row per item or JSON array; item ID/name/category/price/order fields
- purchase completion signal and purchase/order table
- recipient/consent table and how the stable identifier joins to a deliverable email
- optional product master, stock, recommendation, customer attribute/points, suppression, and order-history tables
- whether browser/cart abandonment history is shared for frequency capping

If the Web log is not real-time, explicitly explain that the workflow cannot reliably detect recent abandonment without accepting the source latency. Offer a batch window based on the available data instead of silently assuming real time.

### 3. Confirm cart-abandonment semantics

Use concrete examples and ask the user to decide each rule. Record the answers in the customer configuration before generating SQL:

- What event means “cart activity” (cart page view, add-to-cart event, checkout start, or another event)?
- How long is the inactivity/session boundary?
- How many minutes must elapse before a session becomes eligible?
- What proves a purchase: thank-you page, order record, or both?
- How long after an order should the user be excluded?
- Should the workflow target all cart items or only the latest item / up to N items?
- What happens when the same user has multiple carts or devices?
- Should empty/guest carts be excluded?
- What consent and suppression rules apply?
- What is the per-user frequency cap: same flow per day, all messages per day, or rolling hours?
- What are the schedule and night-window rules?

Translate the answers into explicit `WHERE`, sessionization, purchase exclusion, consent, and frequency-cap clauses. Show a short example such as “cart view at 10:00, purchase at 10:20, workflow at 10:30” and ask whether the person should be sent.

### 4. Decide personalization scope

Ask which fields the email needs:

- cart product fields and maximum item count
- stock/availability and low-stock flags
- recommendation fields and recommendation count
- customer points/attributes
- coupon code/image/description/expiry
- campaign-specific or segment-specific fields

Support these modes:

- cart items only
- cart items plus product/stock enrichment
- cart items plus recommendations
- cart items plus customer attributes
- no personalization beyond recipient and basic cart data

If recommendations are not available or not desired, remove recommendation joins and output empty recommendation fields rather than retaining sample tables. If points/coupons are not used, remove those joins/columns and keep the template contract minimal.

### 5. Configure the workflow

Create a customer copy from the sample and replace placeholders in configuration first. Use clear generic workflow names such as:

- `cart_abandonment`
- `cart_abandonment_nightly`
- `cart_abandonment_send`
- `cart_abandonment_test`

Use one mode-driven test workflow rather than separate first/second/full entry points. Select `smoke`, `fixture`, or `full` with `-p test_mode=...`; keep the SQL fixtures/history queries separate only when their data-selection logic differs.

Parameterize at least:

- target database and table prefix
- Web log source
- recipient and order sources
- identifier/cookie columns
- cart and purchase rules
- schedule/time windows
- output/history table names
- optional enrichment tables
- Engage connection/workspace/campaign identifiers or external connector settings
- template field contract
- test recipients and test message variants

Keep SQL aliases and output field names stable when the destination template expects them. Add or remove fields only after confirming the template/connector contract.

### 6. Build the test-email path

For Engage Studio, create a test workflow that:

1. reads representative rows from the generated send-list or a controlled fixture;
2. replaces the real recipient with the confirmed test address(es), never the live audience;
3. fills missing recommendation, stock, points, coupon, and cart fields with deterministic dummy values so every template branch can be rendered;
4. uses the confirmed test Always-On Campaign ID and Engage connection;
5. supports small staged tests: basic rendering first, then all personalization combinations;
6. logs the expected variants and recipient count.

Ask and confirm:

- exact test email address(es)
- whether plus-address aliases are allowed
- number of variants/messages expected
- which campaign/template receives the test
- whether the test campaign is isolated from production

Do not execute a test send until the recipient, campaign, and expected scope are explicitly confirmed. For an external connector, use its sandbox/test mode where available and verify the destination schema before sending.

### 7. Validate before deployment

Run local/static checks:

- scan all files for residual customer-specific names, domains, UUIDs, account IDs, email addresses, coupon codes, and URLs;
- validate YAML and Digdag structure;
- validate SQL references and destination columns;
- confirm every `${...}` variable is defined by `_export`, workflow parameters, or the documented runtime;
- confirm every source table and column was supplied by the customer;
- verify consent, purchase exclusion, frequency cap, and timezone behavior;
- verify test SQL cannot select live recipients;
- inspect the dry-run task graph before any run.

Report unresolved placeholders explicitly. Do not claim the workflow is production-ready while any required source, campaign, connector, template, consent, or test-recipient input is unresolved.

## Required Interview Record

Maintain a concise configuration record, for example:

```yaml
customer:
  name: "<customer-supplied name>"
delivery:
  route: engage_studio | external_connector
  connection: "<name>"
  workspace_id: "<id>"
  always_on_campaign_ids: []
data:
  weblog: "<db.table>"
  recipients: "<db.table>"
  orders: "<db.table or none>"
  identifier: "<column and hash rule>"
logic:
  cart_rule: "<event/path predicate>"
  purchase_rule: "<predicate>"
  eligibility_delay_minutes: 20
  purchase_exclusion_hours: 48
  session_timeout_seconds: 1800
  frequency_cap: "<rule>"
personalization:
  cart_items: true
  recommendations: false
  stock: false
  points: false
  coupons: false
testing:
  recipients: []
  variants: []
```

Use placeholders such as `<TO_BE_CONFIRMED>` rather than copying values from the reference sample.

## Output Format

When guiding or completing a build, report in this order:

1. **Confirmed configuration** — delivery route, sources, cart/purchase rules, personalization, and test scope.
2. **Workflow artifacts** — paths of the skill, sample, customer copy, SQL, and test entry points.
3. **Pending confirmations** — only blockers or decisions still needed.
4. **Validation status** — checks run, dry-run status, and any unresolved references.
5. **Send safety** — state whether no send occurred, a test send is awaiting confirmation, or a confirmed test was executed with recipient count and campaign.

## Example: Engage Studio Customer

**Input:** “Use our real-time table `shop.web_events`, cart path `/cart`, send through an existing Always-On Campaign, and include cart items but no recommendations.”

**Action:** Ask for the exact event/identifier/item columns, consent table and join, purchase signal/order exclusion, campaign/workspace/connection IDs, template variables, schedule, and test recipients. Remove recommendation joins from the sample and produce only the confirmed cart fields. Validate before presenting a dry-run.

## Example: External Connector Customer

**Input:** “Send abandoned carts to our CRM connector; it needs `email`, `sku`, `quantity`, and `cart_updated_at`.”

**Action:** Ask for connector type/name, destination object, auth setup, consent/suppression rule, one-to-many item handling, timestamp format, and deduplication key. Build a connector-specific SQL projection and use sandbox/test mode before live delivery.

## Edge Cases

- **No real-time data:** state the detection delay and redesign eligibility windows around source freshness.
- **No stable identifier:** do not promise email delivery; request a resolvable recipient join or limit the workflow to an anonymous audience use case.
- **No purchase table/signal:** ask whether a thank-you event is sufficient; otherwise mark purchase exclusion as a production blocker.
- **No recommendation data:** disable recommendation fields and simplify the template contract.
- **Multiple campaigns/templates:** map each output variant to an explicit campaign and test each branch separately.
- **Customer asks to deploy immediately:** still preview and obtain explicit confirmation before any external send.
