ARG BASE_IMAGE=nvidia/cuda:13.0.0-devel-ubuntu24.04
FROM ${BASE_IMAGE} AS build-base

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    autoconf \
    automake \
    bash \
    bison \
    ca-certificates \
    cmake \
    curl \
    flex \
    g++ \
    gfortran \
    git \
    libasound2-dev \
    libffi-dev \
    libjack-jackd2-dev \
    libsndfile1 \
    libsndfile1-dev \
    libtool \
    make \
    ninja-build \
    patch \
    pkg-config \
    python3 \
    python3-dev \
    sox \
    unzip \
    wget \
    zlib1g-dev \
  && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"

WORKDIR /workspace
COPY scripts/build.sh scripts/env.sh scripts/versions.env ./scripts/
RUN chmod +x ./scripts/build.sh

FROM build-base AS openfst-stack
RUN ./scripts/build.sh --stage openfst-stack

FROM openfst-stack AS kaldi
COPY patches/kaldi ./patches/kaldi
RUN ./scripts/build.sh --stage kaldi

FROM kaldi AS python-stack
COPY patches/kalpy ./patches/kalpy
RUN ./scripts/build.sh --stage python-stack

FROM python-stack AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    sqlite3 \
  && rm -rf /var/lib/apt/lists/*
COPY docker ./docker
COPY scripts/smoke-test.sh ./scripts/smoke-test.sh
COPY scripts/smoke ./scripts/smoke
RUN chmod +x ./docker/entrypoint.sh ./scripts/smoke-test.sh

ENTRYPOINT ["./docker/entrypoint.sh"]
CMD ["mfa", "--help"]
