"""
ユーザー間協調フィルタリング: Matrix Factorization

購買ユーザー×商品の相互作用行列を、潜在ユーザー因子と潜在商品因子に
分解し、内積で未購入商品の推薦スコアを計算する。

本サンプルはSurpriseのSVDを使用する明示的フィードバック版。
実運用では、購入数量・購入回数・返品・時間減衰を interaction_value に
反映し、必要に応じてimplicit feedback用のBPR/ALSへ差し替える。
"""

import os
import subprocess
import sys


def _install_runtime_dependencies():
    """Install packages in the active Custom Script Python environment."""
    subprocess.check_call(
        [
            sys.executable,
            "-m",
            "pip",
            "install",
            "--disable-pip-version-check",
            "--no-cache-dir",
            "pandas>=1.5.0",
            "numpy>=1.24.0",
            "scipy>=1.10.0",
            "scikit-surprise>=1.1.3",
        ]
    )


_install_runtime_dependencies()

import pandas as pd
import pytd
from surprise import Dataset, Reader, SVD


_RUNTIME_DEPENDENCIES_READY = True


def _query_dataframe(client, query):
    result = client.query(query)
    return pd.DataFrame(result["data"], columns=result["columns"])


def _load_candidates(client, table_name, rows):
    client.load_table_from_dataframe(
        rows,
        table_name,
        writer="bulk_import",
        if_exists="overwrite",
    )


def run(
    database: str,
    source_table: str,
    output_table: str,
    top_n: int = 10,
    n_factors: int = 50,
    n_epochs: int = 20,
    min_interactions: int = 1,
):
    """Train Matrix Factorization and write per-user recommendation scores."""
    apikey = os.environ["TD_API_KEY"]
    client = pytd.Client(
        apikey=apikey,
        database=database,
        endpoint=os.environ.get("TD_API_SERVER"),
    )

    interactions = _query_dataframe(
        client,
        f"""
        SELECT member_id, product_id, interaction_value
        FROM {database}.{source_table}
        WHERE interaction_value >= {min_interactions}
        """,
    )
    if interactions.empty:
        _load_candidates(
            client,
            f"{database}.{output_table}",
            pd.DataFrame(
                columns=[
                    "key_type",
                    "key_value",
                    "logic_name",
                    "product_id",
                    "score",
                    "rank_in_logic",
                    "reco_reason",
                ]
            ),
        )
        return

    # SurpriseのReaderは明示的評価値を想定するため、購入強度を1〜5へスケールする。
    max_value = max(float(interactions["interaction_value"].max()), 1.0)
    interactions["rating"] = (
        1.0 + 4.0 * interactions["interaction_value"].astype(float) / max_value
    ).clip(1.0, 5.0)

    reader = Reader(rating_scale=(1.0, 5.0))
    dataset = Dataset.load_from_df(
        interactions[["member_id", "product_id", "rating"]],
        reader,
    )
    trainset = dataset.build_full_trainset()

    model = SVD(
        n_factors=n_factors,
        n_epochs=n_epochs,
        random_state=42,
        biased=True,
    )
    model.fit(trainset)

    users = interactions["member_id"].drop_duplicates().tolist()
    products = interactions["product_id"].drop_duplicates().tolist()
    purchased = set(zip(interactions["member_id"], interactions["product_id"]))

    rows = []
    for member_id in users:
        scored = []
        for product_id in products:
            if (member_id, product_id) in purchased:
                continue
            prediction = model.predict(member_id, product_id).est
            scored.append((product_id, float(prediction)))

        scored.sort(key=lambda item: item[1], reverse=True)
        for rank, (product_id, score) in enumerate(scored[:top_n], start=1):
            rows.append(
                {
                    "key_type": "member_id",
                    "key_value": member_id,
                    "logic_name": "user_based_cf",
                    "product_id": product_id,
                    "score": score / 5.0,
                    "rank_in_logic": rank,
                    "reco_reason": "matrix_factorization",
                }
            )

    result = pd.DataFrame(
        rows,
        columns=[
            "key_type",
            "key_value",
            "logic_name",
            "product_id",
            "score",
            "rank_in_logic",
            "reco_reason",
        ],
    )
    _load_candidates(client, f"{database}.{output_table}", result)


if __name__ == "__main__":
    run(
        database=os.environ["TD_DATABASE"],
        source_table=os.environ.get("SOURCE_TABLE", "user_based_cf_interactions"),
        output_table=os.environ.get("OUTPUT_TABLE", "reco_user_based_cf"),
        top_n=int(os.environ.get("TOP_N", "10")),
        n_factors=int(os.environ.get("N_FACTORS", "50")),
        n_epochs=int(os.environ.get("N_EPOCHS", "20")),
        min_interactions=int(os.environ.get("MIN_INTERACTIONS", "1")),
    )
