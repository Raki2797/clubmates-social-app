# ClubMates Backend
<!-- Repository documentation; excluded from runtime deployment. -->

Fastify + TypeScript API backed by Supabase Postgres.

## Setup

```bash
cd backend
nvm use
npm install
cp .env.example .env
npm run migrate
npm run dev
```

Set `DATABASE_URL` to the Supabase Postgres connection string from Project Settings > Database. Keep server-only secrets in `backend/.env`; the iOS app should only talk to this API.

For OTP login in deployed environments, configure `MSG91_AUTH_KEY`, `MSG91_TEMPLATE_ID`, and `MSG91_SENDER_ID`. The backend generates a 6-digit code, stores only its hash in `otp_codes`, sends the code through MSG91, and verifies user-entered codes against the database row. In local development without MSG91 config, `DEV_OTP_CODE` can be used as a bypass.

## Current Scope

- Phone OTP endpoints with database-backed OTP verification and MSG91 delivery.
- JWT access tokens and refresh-token rotation.
- Profile CRUD, venues/check-ins, discovery, swipes/matches, messages, blocks, and reports.
- Postgres migrations matching `docs/BACKEND_ARCHITECTURE.md`.
- Photo comparison via DeepFace for matching any two uploaded images.

Redis, APNs, and Supabase Storage image processing are intentionally left as next integration layers.

## Photo Comparison

The backend exposes `POST /photos/compare`, which accepts two multipart image files named `image1` and `image2` and returns the DeepFace comparison result.

For local development, keep the Python runtime inside `Backend` so this repo does not depend on an external DeepFace install:

```bash
cd Backend
python3.11 -m venv .venv-face
.venv-face/bin/pip install --upgrade pip setuptools wheel
.venv-face/bin/pip install -r requirements-face.txt
```

Set these env vars to enable it:

```bash
FACE_VERIFICATION_PYTHON_BIN=/absolute/path/to/Backend/.venv-face/bin/python
FACE_VERIFICATION_SCRIPT_PATH=/absolute/path/to/Backend/scripts/compare_faces.py
FACE_VERIFICATION_DEEPFACE_HOME=/absolute/path/to/Backend/.deepface-home
```

The Python environment must already have DeepFace and its model dependencies installed. To avoid runtime internet access in production, pre-download the model weights into `FACE_VERIFICATION_DEEPFACE_HOME`.
