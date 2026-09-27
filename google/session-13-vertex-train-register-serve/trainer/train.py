"""
Queen City Trip Analytics · fleet fuel-cost model.

Trains a model that predicts a vehicle's miles per gallon from the attributes
a fleet customer registers, so each fare quote can include fuel cost. The
preprocessing lives inside the saved pipeline, so the serving payload is the
raw attributes and training and serving cannot disagree about scaling.

    python train.py --data gs://.../auto-mpg.data --model ridge|boosted

Vertex AI sets AIP_MODEL_DIR; the pipeline is saved there as model.joblib,
which is the file name the prebuilt scikit-learn prediction container loads.
Data: the UCI Auto MPG dataset (Quinlan, 1993), CC BY 4.0.
"""
import argparse
import os
import subprocess
import tempfile

import joblib
import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import GradientBoostingRegressor
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_absolute_error
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

COLS = ["mpg", "cylinders", "displacement", "horsepower", "weight", "acceleration", "model_year", "origin"]
NUMERIC = ["cylinders", "displacement", "horsepower", "weight", "acceleration", "model_year"]


def fetch(uri):
    if uri.startswith("gs://"):
        local = os.path.join(tempfile.mkdtemp(), "data")
        subprocess.run(["gsutil", "-q", "cp", uri, local], check=True)
        return local
    return uri


ap = argparse.ArgumentParser()
ap.add_argument("--data", required=True)
ap.add_argument("--model", default="ridge", choices=["ridge", "boosted"])
ap.add_argument("--model_dir", default=None, help="where model.joblib goes; defaults to AIP_MODEL_DIR")
args = ap.parse_args()

df = pd.read_csv(fetch(args.data), sep=r"\s+", names=COLS + ["name"], na_values="?", quotechar='"')
df = df.dropna()
# The prediction container passes each instance as a plain list, so the
# pipeline selects columns by position, not by name.
X, y = df[NUMERIC + ["origin"]].to_numpy(), df["mpg"].to_numpy()
Xtr, Xte, ytr, yte = train_test_split(X, y, test_size=0.2, random_state=61913)

pre = ColumnTransformer([("num", StandardScaler(), list(range(len(NUMERIC)))),
                         ("origin", OneHotEncoder(handle_unknown="ignore"), [len(NUMERIC)])])
est = Ridge(alpha=1.0) if args.model == "ridge" else GradientBoostingRegressor(random_state=61913)
pipe = Pipeline([("pre", pre), ("model", est)]).fit(Xtr, ytr)
mae = mean_absolute_error(yte, pipe.predict(Xte))
print(f"model={args.model} rows={len(df)} test_mae_mpg={mae:.2f}")

out = args.model_dir or os.environ.get("AIP_MODEL_DIR", "model-out")
local = os.path.join(tempfile.mkdtemp(), "model.joblib")
joblib.dump(pipe, local)
if out.startswith("gs://"):
    subprocess.run(["gsutil", "-q", "cp", local, out.rstrip("/") + "/model.joblib"], check=True)
else:
    os.makedirs(out, exist_ok=True); os.replace(local, os.path.join(out, "model.joblib"))
print(f"saved {out.rstrip('/')}/model.joblib")
