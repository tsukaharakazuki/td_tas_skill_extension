"""
ML購入確率予測 - 学習・推論テンプレート

実装テンプレートのみを提供する。特徴量・モデル・カテゴリ設計は
クライアント要件に応じて実装すること（本サンプルはscikit-learnの型のみ）。

前提:
- queries/ml_purchase_probability/features.sql の出力が
  ${common.database}.ml_features_purchase_probability に書き込まれている
- 出力先: ${common.database}.ml_purchase_probability_scores
  (member_id, category_id, purchase_probability)
"""

import os

import pandas as pd
import pytd
from sklearn.ensemble import GradientBoostingClassifier


def run(database: str, prediction_window_days: int):
    apikey = os.environ["TD_API_KEY"]
    client = pytd.Client(apikey=apikey, database=database, endpoint=os.environ.get("TD_API_SERVER"))

    features = client.query(f"SELECT * FROM {database}.ml_features_purchase_probability")
    df = pd.DataFrame(features["data"], columns=features["columns"])

    # --- 教師データ作成（サンプル: 観測期間内に購入があったかどうかを正例とする） ---
    # 実運用では prediction_window_days 後の購入有無をラベル化する形に置き換える。
    df["label"] = (df["purchase_count"] > 0).astype(int)

    feature_cols = [
        "pv_count",
        "session_count",
        "distinct_category_count",
        "distinct_brand_count",
        "avg_dwell_seconds",
    ]
    X = df[feature_cols].fillna(0)
    y = df["label"]

    model = GradientBoostingClassifier()
    model.fit(X, y)

    df["purchase_probability"] = model.predict_proba(X)[:, 1]

    # カテゴリ単位のスコアはサンプルとして距離閲覧カテゴリ数を代理指標に使う（テンプレート）
    df["category_id"] = df["distinct_category_count"]

    result = df[["member_id", "category_id", "purchase_probability"]]

    client.load_table_from_dataframe(
        result,
        f"{database}.ml_purchase_probability_scores",
        writer="bulk_import",
        if_exists="overwrite",
    )


if __name__ == "__main__":
    run(
        database=os.environ["TD_DATABASE"],
        prediction_window_days=int(os.environ.get("PREDICTION_WINDOW_DAYS", "30")),
    )
