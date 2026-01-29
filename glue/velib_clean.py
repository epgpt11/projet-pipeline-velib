import sys
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job

from pyspark.sql.functions import (
    col, explode, trim, upper, lower, when,
    to_timestamp, coalesce, regexp_replace
)
from pyspark.sql.types import IntegerType, DoubleType

args = getResolvedOptions(sys.argv, ["JOB_NAME", "RAW_PATH", "CLEAN_PATH"])
raw_path = args["RAW_PATH"]
clean_path = args["CLEAN_PATH"]

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session

job = Job(glueContext)
job.init(args["JOB_NAME"], args)

df = spark.read.json(raw_path)

# results list parsing
flat = (
    df
    .withColumn("r", explode(col("results")))
    .select(
        col("ingested_at"),
        col("date"),
        col("hour"),
        col("r.stationcode").alias("station_id"),
        col("r.name").alias("name"),
        col("r.nom_arrondissement_communes").alias("arrondissement"),
        col("r.is_installed").alias("is_installed"),
        col("r.numbikesavailable").cast(IntegerType()).alias("bikes_i"),
        col("r.numdocksavailable").cast(IntegerType()).alias("docks_i"),
    )
)

# ingested_at -> ingested_ts (case for format)
ingested_clean = regexp_replace(col("ingested_at"), "Z$", "")

flat = flat.withColumn(
    "ingested_ts",
    coalesce(
        to_timestamp(ingested_clean, "yyyy-MM-dd HH:mm:ss.SSS"),
        to_timestamp(ingested_clean, "yyyy-MM-dd HH:mm:ss"),
        to_timestamp(ingested_clean, "yyyy-MM-dd'T'HH:mm:ss.SSSX"),
        to_timestamp(ingested_clean, "yyyy-MM-dd'T'HH:mm:ssX"),
        to_timestamp(ingested_clean)
    )
)

# is_installed -> 1/0
flat = flat.withColumn(
    "is_installed_i",
    when(upper(trim(col("is_installed"))) == "OUI", 1)
    .when(upper(trim(col("is_installed"))) == "NON", 0)
    .when(lower(trim(col("is_installed"))).isin("true", "t", "yes", "y"), 1)
    .when(lower(trim(col("is_installed"))).isin("false", "f", "no", "n"), 0)
    .when(trim(col("is_installed")) == "1", 1)
    .when(trim(col("is_installed")) == "0", 0)
    .otherwise(None)
)

# fill_rate (treatment case 0 division)
flat = flat.withColumn(
    "fill_rate",
    when(
        (col("bikes_i").isNull()) | (col("docks_i").isNull()) | ((col("bikes_i") + col("docks_i")) == 0),
        None
    ).otherwise(
        col("bikes_i").cast(DoubleType()) /
        (col("bikes_i").cast(DoubleType()) + col("docks_i").cast(DoubleType()))
    )
)

typed = flat.select(
    "ingested_ts",
    "station_id",
    "name",
    "arrondissement",
    "is_installed_i",
    "bikes_i",
    "docks_i",
    "fill_rate",
    "date",
    "hour"
)

#save  parquet  (date/hour partition)
(
    typed
    .write
    .mode("append")
    .format("parquet")
    .partitionBy("date", "hour")
    .save(clean_path)
)

job.commit()
