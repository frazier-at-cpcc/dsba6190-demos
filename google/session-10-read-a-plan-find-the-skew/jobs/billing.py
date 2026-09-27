"""
Queen City Trip Analytics · nightly corporate billing.

    spark-submit billing.py generate <BASE> [ROWS]
    spark-submit billing.py <baseline|broadcast|salted|aqe> <BASE>

The fictional South End firm bills its corporate accounts every night by
joining a year of trips to the accounts dimension and summing fares by
account tier and month. Street hails carry the sentinel account_id WALKUP,
which is never invoiced and holds about 60 per cent of trips. That one key
is the skew.

Each variant writes its physical plan to <BASE>/plans/<variant>.txt and its
result to <BASE>/out/<variant>/. The variants differ only in how the join
is executed; the answer is identical.
"""
import sys
from pyspark.sql import SparkSession, functions as F

mode, base = sys.argv[1], sys.argv[2].rstrip("/")
spark = SparkSession.builder.appName(f"qc-billing-{mode}").getOrCreate()

if mode == "generate":
    rows = int(sys.argv[3]) if len(sys.argv) > 3 else 30_000_000
    trips = (spark.range(rows)
             .withColumn("r", F.rand(61910))
             .withColumn("account_id",
                         F.when(F.col("r") < 0.60, F.lit("WALKUP"))
                          .otherwise(F.format_string("A%05d", (F.rand(7) * 5000).cast("int") + 1)))
             .withColumn("pickup_date", F.date_add(F.lit("2025-01-01"), (F.rand(11) * 365).cast("int")))
             .withColumn("fare", F.round(F.rand(13) * 60 + 8, 2))
             .select(F.col("id").alias("trip_id"), "account_id", "pickup_date", "fare"))
    trips.write.mode("overwrite").parquet(f"{base}/data/trips")
    accounts = (spark.range(1, 5001)
                .select(F.format_string("A%05d", F.col("id")).alias("account_id"),
                        F.element_at(F.array(F.lit("standard"), F.lit("preferred"), F.lit("enterprise")),
                                     (F.col("id") % 3 + 1).cast("int")).alias("tier"))
                .unionByName(spark.range(1).select(F.lit("WALKUP").alias("account_id"),
                                                   F.lit("street").alias("tier"))))
    accounts.write.mode("overwrite").parquet(f"{base}/data/accounts")
    print(f"generated {rows:,} trips and 5,001 accounts under {base}/data")
    sys.exit(0)

trips = spark.read.parquet(f"{base}/data/trips")
accounts = spark.read.parquet(f"{base}/data/accounts")

if mode == "broadcast":
    joined = trips.join(F.broadcast(accounts), "account_id")
elif mode == "salted":
    SALTS = 32
    t = trips.withColumn("salt", (F.rand(3) * SALTS).cast("int"))
    a = accounts.withColumn("salt", F.explode(F.sequence(F.lit(0), F.lit(SALTS - 1))))
    joined = t.join(a, ["account_id", "salt"]).drop("salt")
else:  # baseline and aqe differ only in configuration passed at submit time
    joined = trips.join(accounts, "account_id")

result = (joined.groupBy("tier", F.date_trunc("month", "pickup_date").alias("month"))
          .agg(F.count("*").alias("trips"), F.round(F.sum("fare"), 2).alias("revenue")))

plan = result._jdf.queryExecution().explainString(
    spark._jvm.org.apache.spark.sql.execution.ExplainMode.fromString("formatted"))
spark.range(1).select(F.lit(plan).alias("plan")).coalesce(1).write.mode("overwrite").text(f"{base}/plans/{mode}")
result.write.mode("overwrite").parquet(f"{base}/out/{mode}")
print(f"{mode}: {result.count()} result rows")
