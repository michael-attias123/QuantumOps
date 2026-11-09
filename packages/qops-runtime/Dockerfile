# syntax=docker/dockerfile:1.7
# qops-runtime: the `qops` CLI with the local runtime and the Aer provider, for linux/amd64 and linux/arm64.
# Build from the repo root:  docker build -f packages/qops-runtime/Dockerfile .

FROM python:3.12-slim-bookworm AS build
COPY --from=ghcr.io/astral-sh/uv:0.11.32 /uv /usr/local/bin/uv
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    UV_PROJECT_ENVIRONMENT=/opt/venv
WORKDIR /src
# Dependencies first (cached unless uv.lock changes), then the workspace packages.
COPY pyproject.toml uv.lock .python-version ./
COPY packages/ packages/
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev --no-editable --package qops-cli

FROM python:3.12-slim-bookworm
LABEL org.opencontainers.image.source="https://github.com/michael-attias123/QuantumOps" \
      org.opencontainers.image.description="QuantumOps runtime: qops CLI, local runtime, Aer provider"
COPY --from=build /opt/venv /opt/venv
COPY research/algorithms/ /app/research/algorithms/
ENV PATH=/opt/venv/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
WORKDIR /app
USER 65532:65532
ENTRYPOINT ["qops"]
CMD ["--help"]
