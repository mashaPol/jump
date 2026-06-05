from __future__ import annotations
from pydantic import BaseModel


# ── Locations ──────────────────────────────────────────────────────────────

class LocationIn(BaseModel):
    name: str
    address: str = ""
    description: str = ""
    capacity: int = 1


class LocationOut(LocationIn):
    id: int

    class Config:
        from_attributes = True


# ── Tasks ──────────────────────────────────────────────────────────────────

class TaskIn(BaseModel):
    name: str
    description: str = ""
    duration_hours: float
    people_needed: int = 1


class TaskOut(TaskIn):
    id: int

    class Config:
        from_attributes = True


# ── Availability Slots ─────────────────────────────────────────────────────

class SlotIn(BaseModel):
    date: str        # "YYYY-MM-DD"
    start_time: str  # "HH:MM"
    end_time: str    # "HH:MM"


class SlotOut(SlotIn):
    id: int
    person_id: int

    class Config:
        from_attributes = True


# ── People ─────────────────────────────────────────────────────────────────

class PersonIn(BaseModel):
    name: str
    email: str = ""


class PersonOut(PersonIn):
    id: int
    availability_slots: list[SlotOut] = []

    class Config:
        from_attributes = True


# ── Timetable ──────────────────────────────────────────────────────────────

class TimetableEntryOut(BaseModel):
    id: int
    person_id: int | None
    task_id: int | None
    location_id: int | None
    date: str
    start_time: str
    end_time: str
    is_manual: bool
    notes: str
    person_name: str | None = None
    task_name: str | None = None
    location_name: str | None = None

    class Config:
        from_attributes = True


class TimetableEntryPatch(BaseModel):
    person_id: int | None = None
    task_id: int | None = None
    location_id: int | None = None
    date: str | None = None
    start_time: str | None = None
    end_time: str | None = None
    notes: str | None = None
    is_manual: bool = True
