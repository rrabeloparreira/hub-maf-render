FROM mcr.microsoft.com/playwright/python:v1.55.0-noble

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

COPY bootstrap.sh /usr/local/bin/hub-bootstrap
RUN chmod +x /usr/local/bin/hub-bootstrap

ENTRYPOINT ["/usr/local/bin/hub-bootstrap"]
