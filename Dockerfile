# syntax=docker/dockerfile:1

FROM --platform=$BUILDPLATFORM node:20-bookworm-slim AS frontend
WORKDIR /src

RUN npm install --global pnpm@9
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

COPY plugin.json rollup.config.js tsconfig.json ./
COPY src/ src/
COPY assets/ assets/
RUN pnpm run build

FROM python:3.14-slim-bookworm AS package
ARG TARGETARCH
RUN test "$TARGETARCH" = arm64 || { echo "Build this image for linux/arm64." >&2; exit 1; }

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl libgl1 libglib2.0-0 libgomp1 \
    && rm -rf /var/lib/apt/lists/*

ENV DEPS_DIR=/opt/decky-dependencies
ENV WORKER_PYTHON=/opt/decky-dependencies/python313/python/bin/python3.13
WORKDIR /src

# Use the same relocatable worker and checksum as the ARM64 CI workflow.
RUN mkdir -p "$DEPS_DIR/python313" \
    && curl --fail --location --retry 3 --output /tmp/decky-python.tar.gz \
        'https://github.com/astral-sh/python-build-standalone/releases/download/20260408/cpython-3.13.13%2B20260408-aarch64-unknown-linux-gnu-install_only_stripped.tar.gz' \
    && printf '%s  %s\n' \
        'f06466ac56cdc185d61190ea89f9c4e84ff4fc03ac08793151970a1fea86410b' \
        /tmp/decky-python.tar.gz | sha256sum --check \
    && tar -xzf /tmp/decky-python.tar.gz -C "$DEPS_DIR/python313" \
    && rm /tmp/decky-python.tar.gz

COPY requirements.txt ./
RUN "$WORKER_PYTHON" -m pip install --only-binary=:all: --no-compile --no-cache-dir \
        -r requirements.txt --target "$DEPS_DIR/py_modules" \
    && python -m pip install --only-binary=:all: --no-compile --no-cache-dir \
        'Pillow>=12,<13' --target "$DEPS_DIR/loader_py_modules/cp314" \
    && rm -rf "$DEPS_DIR/py_modules/rapidocr/models" \
    && mkdir "$DEPS_DIR/py_modules/rapidocr/models"

RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc libc6-dev linux-libc-dev \
    && rm -rf /var/lib/apt/lists/* \
    && python -m pip install --no-deps --no-compile --no-cache-dir \
        'evdev==2.0.0' --target "$DEPS_DIR/loader_py_modules/cp314"

RUN PYTHONPATH="$DEPS_DIR/py_modules" "$WORKER_PYTHON" -S \
        -c 'import cv2, ctranslate2, numpy, onnxruntime, rapidocr, sentencepiece; from PIL import Image' \
    && PYTHONPATH="$DEPS_DIR/loader_py_modules/cp314:$DEPS_DIR/py_modules" python -S \
        -c 'import evdev; from PIL import Image; evdev.list_devices(); Image.new("RGB", (4, 4)).tobytes()'

COPY LICENSE README.md THIRD_PARTY_LICENSES main.py package.json plugin.json ./
COPY py_modules/providers/ py_modules/providers/
COPY scripts/package_arm64.py scripts/package_arm64.py
COPY --from=frontend /src/dist/ dist/
RUN python scripts/package_arm64.py "$DEPS_DIR" /export/Decky-Translator-arm64.zip

FROM scratch AS artifact
COPY --from=package /export/Decky-Translator-arm64.zip /
