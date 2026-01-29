import json
import os
import urllib.request
from datetime import datetime, timezone

import boto3

# OpenData Paris - Vélib disponibilité en temps réel (API v2.1)
BASE_URL = "https://opendata.paris.fr/api/explore/v2.1/catalog/datasets/velib-disponibilite-en-temps-reel/records"

s3 = boto3.client("s3")


def fetch_all_records(limit=100):
    """
    Récupère tous les enregistrements via pagination (offset).
    La plupart du temps il y a ~1500 stations, donc 100/page c'est OK.
    """
    all_results = []
    offset = 0

    while True:
        url = f"{BASE_URL}?limit={limit}&offset={offset}"

        with urllib.request.urlopen(url, timeout=20) as resp:
            payload = json.loads(resp.read().decode("utf-8"))

        results = payload.get("results", [])
        all_results.extend(results)

       
        if len(results) < limit:
            break

        offset += limit

        
        if offset > 50000:
            break

    return all_results


def lambda_handler(event, context):
    bucket = os.environ.get("BUCKET_NAME")
    if not bucket:
        return {"statusCode": 500, "body": "Missing BUCKET_NAME environment variable"}

    # Timestamp stable en UTC
    now = datetime.now(timezone.utc)
    date_str = now.strftime("%Y-%m-%d")
    hour_str = now.strftime("%H")
    file_ts = now.strftime("%Y%m%d_%H%M%S")

    # 1) Fetch API
    try:
        records = fetch_all_records(limit=100)
    except Exception as e:
        return {"statusCode": 500, "body": f"API fetch failed: {str(e)}"}

    # 2) Payload stocké en raw (on garde tout)
    output = {
        "source": "velib",
        "ingested_at": now.isoformat(),
        "record_count": len(records),
        "results": records
    }

    # 3) Chemin S3 selon 
    key = (
        f"raw/source=velib/date={date_str}/hour={hour_str}/"
        f"velib_{file_ts}.json"
    )

    # 4) Write S3
    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=json.dumps(output, ensure_ascii=False).encode("utf-8"),
        ContentType="application/json"
    )

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "OK",
            "bucket": bucket,
            "key": key,
            "record_count": len(records)
        })
    }