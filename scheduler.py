from __future__ import annotations
from sqlalchemy.orm import Session
from models import AvailabilitySlot, Location, Person, Task, TimetableEntry


def _to_minutes(time_str: str) -> int:
    h, m = time_str.split(":")
    return int(h) * 60 + int(m)


def _from_minutes(total: int) -> str:
    return f"{total // 60:02d}:{total % 60:02d}"


def generate_timetable(db: Session) -> list[TimetableEntry]:
    tasks = db.query(Task).all()
    locations = db.query(Location).order_by(Location.capacity.desc()).all()
    people = db.query(Person).all()
    slots = db.query(AvailabilitySlot).all()

    # free_windows[person_id] = [(date, start_min, end_min), ...]
    free_windows: dict[int, list[tuple[str, int, int]]] = {p.id: [] for p in people}
    for slot in slots:
        free_windows[slot.person_id].append(
            (slot.date, _to_minutes(slot.start_time), _to_minutes(slot.end_time))
        )

    # Sort tasks: most people needed first, then longest duration
    sorted_tasks = sorted(tasks, key=lambda t: (-t.people_needed, -t.duration_hours))

    # busy[person_id] = [(date, start_min, end_min), ...]
    busy: dict[int, list[tuple[str, int, int]]] = {p.id: [] for p in people}

    def is_free(person_id: int, date: str, start: int, end: int) -> bool:
        for b_date, b_start, b_end in busy[person_id]:
            if b_date == date and not (end <= b_start or start >= b_end):
                return False
        return True

    def find_window(person_id: int, date: str, duration_min: int) -> int | None:
        """Return earliest start_min where person is free for duration on date."""
        for w_date, w_start, w_end in free_windows[person_id]:
            if w_date != date:
                continue
            if w_end - w_start < duration_min:
                continue
            if is_free(person_id, date, w_start, w_start + duration_min):
                return w_start
        return None

    def pick_location(people_count: int) -> Location | None:
        for loc in locations:
            if loc.capacity >= people_count:
                return loc
        return locations[0] if locations else None

    new_entries: list[TimetableEntry] = []

    for task in sorted_tasks:
        duration_min = int(task.duration_hours * 60)

        # Gather all (person_id, date, start_min) candidates grouped by date
        candidates_by_date: dict[str, list[tuple[int, int]]] = {}
        for person in people:
            for w_date, w_start, w_end in free_windows[person.id]:
                if w_end - w_start < duration_min:
                    continue
                start = find_window(person.id, w_date, duration_min)
                if start is None:
                    continue
                candidates_by_date.setdefault(w_date, []).append((person.id, start))

        # Pick date with most candidates, preferring to meet people_needed
        chosen_date = None
        chosen_candidates: list[tuple[int, int]] = []
        for date, cands in sorted(candidates_by_date.items()):
            if len(cands) >= task.people_needed:
                chosen_date = date
                chosen_candidates = cands[: task.people_needed]
                break
        else:
            # Take best available date even if understaffed
            if candidates_by_date:
                chosen_date, chosen_candidates = max(
                    candidates_by_date.items(), key=lambda kv: len(kv[1])
                )

        if not chosen_date:
            continue

        location = pick_location(len(chosen_candidates))
        shortfall = task.people_needed - len(chosen_candidates)
        notes = f"Needs {shortfall} more person(s)" if shortfall > 0 else ""

        for person_id, start_min in chosen_candidates:
            end_min = start_min + duration_min
            entry = TimetableEntry(
                person_id=person_id,
                task_id=task.id,
                location_id=location.id if location else None,
                date=chosen_date,
                start_time=_from_minutes(start_min),
                end_time=_from_minutes(end_min),
                is_manual=False,
                notes=notes,
            )
            db.add(entry)
            busy[person_id].append((chosen_date, start_min, end_min))
            new_entries.append(entry)

    db.commit()
    for e in new_entries:
        db.refresh(e)
    return new_entries
