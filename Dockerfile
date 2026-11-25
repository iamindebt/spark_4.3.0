FROM python:3.12-slim-trixie

LABEL org.opencontainers.image.title="spark-expanse-2026" \
      org.opencontainers.image.description="PySpark and scientific computing environment for SDSC Expanse" \
      org.opencontainers.image.source="https://github.com/USERNAME/spark-expanse-2026"

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash curl ca-certificates git jq procps \
    openjdk-21-jre-headless \
    && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
ENV PATH="${JAVA_HOME}/bin:${PATH}"
ENV PYSPARK_PYTHON=/usr/local/bin/python

COPY requirements.txt /tmp/requirements.txt

RUN python -m pip install --upgrade pip && \
    python -m pip install -r /tmp/requirements.txt && \
    python -m pip check && \
    rm /tmp/requirements.txt

RUN java -version

RUN python -c "import pyspark, plotly, pandas, numpy, pyarrow; print('PySpark:', pyspark.__version__); print('Plotly:', plotly.__version__)"

RUN python -c "from pyspark.sql import SparkSession; spark = SparkSession.builder.master('local[2]').appName('ContainerTest').getOrCreate(); print('Spark JVM:', spark.version); assert spark.range(5).count() == 5; spark.stop()"

CMD ["/bin/bash"]
