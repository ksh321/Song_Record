# Linux amd64 runtime manifest verified 2026-10-13; no application secrets in build context.
FROM eclipse-temurin:21-jre-noble@sha256:7fd597bf48c8bb13a7a3fb227f8366dec0423f78775d4b4f7e30409204af8627
RUN apt-get update && apt-get install -y --no-install-recommends python3 ffmpeg && rm -rf /var/lib/apt/lists/* \
    && groupadd -g 10001 songrecord && useradd -u 10001 -g songrecord -M songrecord
COPY api.jar /app/api.jar
COPY start-api.sh /app/start-api.sh
COPY inject-runtime.py /app/inject-runtime.py
USER 10001:10001
ENTRYPOINT ["sh", "/app/start-api.sh"]
