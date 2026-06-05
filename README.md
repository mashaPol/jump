# Jump — Calculator & Availability Timetable Planner

A FastAPI web application with two tools: a calculator and an availability-based timetable planner.

---

## Running the app

```bash
pip install -r requirements.txt
uvicorn main:app --reload
```

Visit `http://127.0.0.1:8000` for the calculator, or `http://127.0.0.1:8000/planner` for the timetable planner.

> **Note:** The entry point changed from `calculator:app` to `main:app` when the planner was added.

---

## Project structure

```
main.py               Entry point — wires both routers, serves static pages, creates DB tables on startup
calculator.py         Safe AST-based expression evaluator (logic only, no FastAPI app)
database.py           SQLAlchemy engine, session factory, get_db dependency
models.py             ORM table definitions (5 tables)
schemas.py            Pydantic request/response models
scheduler.py          Greedy timetable auto-generation algorithm
routers/
  calc.py             POST /api/calc
  planner.py          Full CRUD + timetable generate/clear under /api/planner
static/
  index.html          Calculator UI
  planner.html        Timetable planner SPA
  css/style.css       Shared dark theme (calculator)
  css/planner.css     Dark theme extensions for the planner
  js/app.js           Calculator frontend
  js/planner.js       Planner frontend (vanilla JS, no framework)
planner.db            SQLite database (auto-created, git-ignored)
```

---

## Timetable planner

### Concept

The planner answers: **WHO does WHAT at WHAT location and when.**

Data is collected in three categories before generating a timetable:

| Entity | What it represents |
|---|---|
| **Locations** | Physical places where tasks happen (name, address, capacity) |
| **Tasks** | Work to be scheduled (name, duration in hours, number of people needed) |
| **People & Availability** | People and the time windows when each is available (date + start/end time) |

Once data is entered, clicking **Generate Timetable** runs the auto-assignment algorithm and produces a timetable. Each entry can be manually edited after generation; manually edited rows are preserved across re-generations.

### Database schema

```
locations          id, name*, address, description, capacity
tasks              id, name*, description, duration_hours, people_needed
people             id, name*, email
availability_slots id, person_id → people, date, start_time, end_time
timetable_entries  id, person_id → people, task_id → tasks, location_id → locations,
                   date, start_time, end_time, is_manual, notes
```

`*` unique constraint. Availability slots cascade-delete with their person. Timetable entries set FK columns to NULL when a referenced entity is deleted (the entry row is kept as an unassigned record).

### Auto-generation algorithm (`scheduler.py`)

The algorithm is a greedy single-pass slot-filler:

1. Load all tasks, locations, and people with their availability slots.
2. Build a map of free time windows per person (`person_id → [(date, start_min, end_min)]`).
3. Sort tasks by `people_needed` descending, then `duration_hours` descending (hardest-to-fill tasks go first).
4. For each task, find candidate (person, date, window) tuples where the window is long enough and the person is not already busy. Group by date, pick the earliest date that has enough candidates to meet `people_needed`.
5. Assign a location — prefer one whose capacity covers the number of assignees; fall back to the largest available.
6. Create `TimetableEntry` rows (`is_manual=False`) and mark the used intervals as busy to prevent double-booking.
7. If a date with enough people cannot be found, assign whoever is available and record the shortfall in the entry's `notes` field.

Re-generating clears all `is_manual=False` entries and re-runs the algorithm from scratch. Entries where `is_manual=True` are never touched by generation.

### API endpoints

All planner endpoints are under `/api/planner`.

```
Locations
  GET    /locations
  POST   /locations          body: { name, address, description, capacity }
  PUT    /locations/{id}     body: same as POST
  DELETE /locations/{id}

Tasks
  GET    /tasks
  POST   /tasks              body: { name, description, duration_hours, people_needed }
  PUT    /tasks/{id}
  DELETE /tasks/{id}

People
  GET    /people             includes nested availability_slots[]
  POST   /people             body: { name, email }
  PUT    /people/{id}
  DELETE /people/{id}

Availability slots
  POST   /people/{id}/slots  body: { date, start_time, end_time }  (date: YYYY-MM-DD, times: HH:MM)
  DELETE /slots/{slot_id}

Timetable
  GET    /timetable          returns entries sorted by date, start_time
  POST   /timetable/generate clears non-manual entries, runs scheduler, returns full timetable
  PUT    /timetable/{id}     patch any field; always sets is_manual=True
  DELETE /timetable/{id}     remove one entry
  DELETE /timetable          clear all entries
```

---

## Calculator

A stateless expression evaluator. The frontend sends expressions as strings; the backend parses them with Python's `ast` module and evaluates only safe numeric operations — no `eval()`, no imports, no function calls.

```
POST /api/calc
  Request:  { "expression": "3+4*2" }
  Response: { "expression": "3+4*2", "result": 11 }
```

Supported operators: `+  -  *  /  //  %  **` and parentheses. Raises HTTP 400 for invalid or unsafe expressions.

---

## Design decisions

**Single-file SQLite database** — no separate database server to run or configure. The file (`planner.db`) is created automatically on first startup. Sufficient for the expected scale (tens to hundreds of rows).

**Synchronous SQLAlchemy sessions with sync route handlers** — keeps the code straightforward. FastAPI supports both sync and async handlers; sync is simpler when using SQLite without an async driver.

**No frontend framework** — the planner UI is plain HTML + vanilla JS. State is kept in a module-level object and the relevant section of the DOM is re-rendered after each mutation. Avoids a build step and keeps the dependency count at zero on the frontend.

**Greedy scheduler, no backtracking** — a full constraint-satisfaction solver would be overkill for human-scale data. The greedy approach (hardest tasks first, earliest available date) produces good-enough results in linear time, and the manual-correction UI handles edge cases the algorithm can't resolve.

**Manual edits survive re-generation** — `is_manual=True` rows are skipped during generation. This lets users fix algorithmically awkward assignments once without losing them every time new data is added.

**`calculator.py` kept as a logic module** — the original file's `app` object is no longer the uvicorn entry point, but the `safe_eval` and `_evaluate` functions are imported by `routers/calc.py`. Avoids rewriting working code.
