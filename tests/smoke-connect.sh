#!/usr/bin/env bash
# Runs during image build; standard Spark is tested separately in Dockerfile.
set -euo pipefail
python - <<'PY'
import os
from pathlib import Path
from zipfile import ZipFile
import pyspark
assert Path(os.environ['SPARK_HOME']).resolve() == Path(pyspark.__file__).resolve().parent
assert int(pyspark.__version__.split('.')[0]) >= 4, pyspark.__version__
server_class = 'org/apache/spark/sql/connect/service/SparkConnectServer.class'
assert any(server_class in ZipFile(jar).namelist() for jar in Path(os.environ['SPARK_HOME'], 'jars').glob('spark-connect_*.jar')), 'Missing JVM Connect server'
print('Resolved PySpark:', pyspark.__version__, flush=True)
PY
"$SPARK_HOME/bin/spark-submit" --version
if ss -H -ltn 'sport = :15002' | grep -q .; then
    echo 'Port 15002 already occupied' >&2
    exit 1
fi
log=$(mktemp)
server_pid=
cleanup() {
    if [[ -n "$server_pid" ]]; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    cat "$log"
    rm -f "$log"
}
trap cleanup EXIT
"$SPARK_HOME/bin/spark-submit" \
  --class org.apache.spark.sql.connect.service.SparkConnectServer \
  --master 'local[2]' \
  --driver-memory 4g \
  --conf spark.connect.grpc.binding.address=127.0.0.1 \
  --conf spark.connect.grpc.binding.port=15002 \
  spark-internal >"$log" 2>&1 &
server_pid=$!
ready=false
for attempt in {1..90}; do
    kill -0 "$server_pid" || exit 1
    if ss -H -ltn 'sport = :15002' | grep -q '127.0.0.1:15002'; then
        ready=true
        break
    fi
    sleep 1
done
[[ "$ready" == true ]] || { echo 'Connect startup timed out' >&2; exit 1; }
timeout 120s python - <<'PY'
import pyspark
from pyspark.sql import SparkSession
from pyspark.sql.connect.session import SparkSession as ConnectSession
spark = SparkSession.builder.remote('sc://127.0.0.1:15002').getOrCreate()
try:
    assert isinstance(spark, ConnectSession)
    assert spark.version == pyspark.__version__
    assert spark.range(5).count() == 5
    assert spark.sql('SELECT 42 AS answer').first().answer == 42
    assert len(spark.range(3).toPandas()) == 3
    assert spark.range(3).plot.line(x='id', y='id') is not None
    print('Standalone Spark Connect smoke test passed:', spark.version)
finally:
    spark.stop()
PY
