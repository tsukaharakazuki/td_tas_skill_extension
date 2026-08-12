# Cart Abandonment Workflow Sample

Customer-agnostic Treasure Data Workflow (Digdag) reference for detecting eligible abandoned carts, preparing a send list, and optionally delivering through an Engage Studio Always-On Campaign.

This directory is a template only. It contains no customer credentials and must not be deployed without completing `config/params.example.yml` and the interview in `cart-abandonment-workflow/SKILL.md`.

## Included flow

1. Read a real-time or batch Web log source.
2. Sessionize visitor activity.
3. Identify cart-abandonment candidates after an inactivity delay.
4. Exclude purchasers, unsubscribed users, suppressed users, and frequency-cap violations.
5. Enrich cart items with optional product, stock, recommendation, points, or coupon data.
6. Create a stable send-list table.
7. Optionally export to Engage Studio through a configured Always-On Campaign.
8. Provide one mode-driven test workflow that replaces recipients and fills template variables with deterministic fixtures.

The test entry point is `send_email_test.dig`. Select a test scope with `-p test_mode=smoke`, `-p test_mode=fixture`, or `-p test_mode=full`; separate `.dig` files for each test phase are intentionally avoided.

```bash
tdx wf run cart_abandonment.send_email_test -p test_mode=smoke
tdx wf run cart_abandonment.send_email_test -p test_mode=fixture
tdx wf run cart_abandonment.send_email_test -p test_mode=full
```

Before any test send, set the test recipient and isolated test campaign in the customer configuration and confirm the expected message count.

The SQL files remain separate where their data-selection logic differs: smoke samples representative history rows, fixture builds controlled combinations, and full covers available history patterns.

    
## Customer configuration required

- database and output table prefix
- Web log source and freshness
- identifier/cookie and item columns
- cart and purchase predicates
- recipient/consent source
- order exclusion window and frequency cap
- personalization fields and template contract
- Engage Studio campaign/workspace/connection or external connector mapping
- test recipients and test campaign

## Naming policy

The sample intentionally uses generic names such as `cart_abandonment`, `source_web_events`, and `target_cart_send_list`. Replace every `<TO_BE_CONFIRMED>` value in the customer copy. Do not add customer names, internal account IDs, real addresses, credentials, or production campaign IDs to this sample.

## Safety

Run validation and a dry-run first. A dry-run is not a send. Obtain explicit confirmation before running a test or production workflow that invokes an external connector or Engage Studio campaign.
