# FastAPI Calculator

A lightweight FastAPI application that serves a modern calculator UI and exposes a JSON API at `/api/calc`.

## Run locally

```bash
python -m pip install -r requirements.txt
uvicorn calculator:app --reload
```

Then visit `http://127.0.0.1:8000` in your browser.

## API

- `POST /api/calc`
  - Request JSON: `{ "expression": "2+3*4" }`
  - Response JSON: `{ "expression": "2+3*4", "result": 14 }`
