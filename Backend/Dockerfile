FROM node:22-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_NO_CACHE_DIR=1
ENV PYTHONUNBUFFERED=1
ENV HOST=0.0.0.0
ENV PORT=3000
ENV FACE_VERIFICATION_PYTHON_BIN=/app/.venv-face/bin/python
ENV FACE_EMBEDDING_SCRIPT_PATH=/app/scripts/extract_embedding.py
ENV FACE_VERIFICATION_DEEPFACE_HOME=/app/.deepface-home
ENV FACE_VERIFICATION_MODEL=ArcFace
ENV FACE_VERIFICATION_DETECTOR=scrfd
ENV FACE_VERIFICATION_THRESHOLD=0.70
ENV FACE_ANTI_SPOOF_MODEL_PATH=/app/models/minifasnet_v2.onnx
ENV FACE_ANTI_SPOOF_THRESHOLD=0.50

WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    libgl1 \
    libglib2.0-0 \
    libgomp1 \
    libsm6 \
    libxext6 \
    libxrender1 \
    python3 \
    python3-pip \
    python3-venv \
  && rm -rf /var/lib/apt/lists/*

COPY package*.json ./
RUN npm ci

COPY requirements-face.txt ./
RUN python3 -m venv .venv-face \
  && .venv-face/bin/pip install --upgrade pip setuptools wheel \
  && .venv-face/bin/pip install -r requirements-face.txt

COPY . .

RUN npm run build \
  && npm prune --omit=dev

EXPOSE 3000

CMD ["node", "dist/server.js"]
