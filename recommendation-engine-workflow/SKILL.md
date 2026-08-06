---
name: recommendation-engine-workflow
description: Use when the user asks to finalize, customize, deploy, validate, or explain the recommendation-engine Treasure Workflow sample for a client. Triggers on recommendation workflow, recommender WF, レコメンドWorkflow, Matrix Factorization recommendation, client-specific recommendation logic, or requests to configure the sample's logics, tables, keys, top-N, weights, or deployment. Guides Treasure AI Studio through data discovery, config mapping, Hive SQL and Python Custom Script updates, validation, dry-run, and deployment.
---

# Recommendation Engine Workflow Finalizer

Client-specific recommendation implementations from the reusable `recommendation-engine` sample. Keep the sample architecture intact unless the client's data model or KPI requires a deliberate extension.

## Inputs to collect

Before editing, identify:

- Web log database/table and columns for time, member ID, cookie/td_client_id, event type, product, category, brand, session, dwell time, and search.
- Order database/table and columns for time, order ID, member ID, product, category, brand, quantity, amount, and order status.
- Product master database/table and columns for product, category, brand, price, stock, sale status, target attributes, and margin if available.
- Member database/table and columns for member ID, gender, age band, area, rank, registration date, and consent flags.
- Cookie/td_client_id to member ID mapping table, if anonymous-to-known stitching is required.
- Recommendation destination, refresh frequency, KPI, output key, and per-user top-N.
- Whether impression/click/cart/purchase logs exist for bandit optimization.

Do not invent client table names or column names. Ask for missing mappings or inspect metadata with the appropriate TD tools first.

## Workflow architecture

Preserve this flow:

```text
parent recommendation-engine.dig
  -> enabled child logics/*.dig (parallel)
  -> reco_all_candidates
  -> final/final_output.dig
  -> reco_final_output
```

Each candidate row must retain:

```text
key_type, key_value, logic_name, product_id, score, rank_in_logic, reco_reason
```

The final result must retain the adopted logic and reason so the business user can explain why a product was recommended.

## Implementation procedure

1. Copy or branch the sample for the client. Do not overwrite the reusable sample with client-specific values.
2. Update `config/params.yml` first. Change source databases/tables, key columns, lookback periods, per-logic `top_n`, enable flags, final weights, diversity limits, and exclusion rules there.
3. Confirm every configured column exists. Pay special attention to `event_type` values (`view`, `pageview`, `cart_add`, `favorite_add`) and timestamp units.
4. Enable only logic supported by the client's data. Keep `ml_purchase_probability` disabled until a time-based label and adequate training data exist. Keep `bandit_optimization` disabled until impression and outcome logs are available.
5. For user-based CF, use `logics/user_based_cf.dig`: aggregate interactions with SQL, then run `tasks/user_based_cf/matrix_factorization.py` with Python Custom Script and SVD Matrix Factorization. Keep `.dig` parameter names aligned with Python function argument names.
6. Install runtime Python dependencies with `sys.executable -m pip install` before importing optional packages. Pin versions after a successful Custom Script test. Use the supported Custom Script Python image and confirm outbound access/IP allowlisting when PyPI access is required.
7. Validate the training population, sparsity, and output volume. Add a fallback to bestseller/category logic for users without enough history.
8. Validate the Workflow structure before any remote action. Check that every `call>` target and SQL path exists, every `insert_into` table has a compatible schema, and the manifest reads/writes match actual tables.
9. Run a safe client-data test or dry-run first. Inspect candidate counts, null keys, duplicate user-product rows, purchased-product exclusion, stock filtering, category/brand caps, and final top-N counts.
10. Only after explicit confirmation, push or run against the client's TD environment. For external-side-effect operations, preview first and explain scope. Never assume deployment approval from approval of code edits.

## Logic selection guide

- New or anonymous users: `bestseller_overall`, `bestseller_category`, `attribute_fit`.
- Recent browsing: `browsing_history`, `attribute_similarity`, `item_cooccurrence`.
- Cart or favorite activity: `cart_favorite`, then complementary/basket candidates.
- Repeat-purchase businesses: `repurchase`, `basket_association`, `rfm_stage`.
- Large purchase history and catalog: `user_based_cf` with Matrix Factorization.
- Seasonal or campaign-driven demand: `time_seasonality`.
- Sufficient impression and outcome logs: `bandit_optimization`.
- Mature feature and label data: `ml_purchase_probability`.

Use multiple candidates rather than relying on one model. Start with explainable rules, then add CF/ML after data quality and evaluation are established.

## Quality checks

Check these before reporting completion:

- No hard-coded client-specific source tables remain in SQL or Python.
- `key_type` matches the configured key column and no null `key_value` rows enter the final output.
- User-based CF excludes products already purchased and handles unknown users/items safely.
- Python package installation occurs before optional imports.
- The SVD candidate output is bounded by `top_n` and does not explode as users × products.
- Final weights include every enabled logic and disabled logic does not contribute candidates.
- Out-of-stock, sale-status, recent-purchase, category, and brand rules match the client's business policy.
- Recommendation reasons are human-readable.
- Workflow validation passes.
- Deployment/run status is reported truthfully; do not claim a remote run if only local validation was performed.

## Output format

Report:

1. Client mapping and assumptions.
2. Enabled/disabled logic table with reasons.
3. Files changed.
4. Validation results and sample data checks.
5. Deployment status and exact next approval required.
6. Known limitations and recommended follow-ups.

## Example

**Input:** `会員IDと購買履歴があるEC顧客向けに、購入履歴を使ったレコメンドを追加したい`

**Action:** Map the order table in `config/params.yml`, confirm `member_id`, `product_id`, `time`, `quantity`, and `order_id`, enable `user_based_cf`, keep the SQL interaction extraction, run the Python SVD task, validate sparsity and purchased-item exclusion, then ask for confirmation before push/run.
