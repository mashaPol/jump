from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from database import get_db
from models import AvailabilitySlot, Location, Person, Task, TimetableEntry
from schemas import (
    LocationIn, LocationOut,
    TaskIn, TaskOut,
    PersonIn, PersonOut,
    SlotIn, SlotOut,
    TimetableEntryOut, TimetableEntryPatch,
)
import scheduler as sched

router = APIRouter()


def _entry_out(e: TimetableEntry) -> TimetableEntryOut:
    return TimetableEntryOut(
        id=e.id,
        person_id=e.person_id,
        task_id=e.task_id,
        location_id=e.location_id,
        date=e.date,
        start_time=e.start_time,
        end_time=e.end_time,
        is_manual=e.is_manual,
        notes=e.notes or "",
        person_name=e.person.name if e.person else None,
        task_name=e.task.name if e.task else None,
        location_name=e.location.name if e.location else None,
    )


# ── Locations ──────────────────────────────────────────────────────────────

@router.get("/locations", response_model=list[LocationOut])
def list_locations(db: Session = Depends(get_db)):
    return db.query(Location).all()


@router.post("/locations", response_model=LocationOut, status_code=201)
def create_location(data: LocationIn, db: Session = Depends(get_db)):
    loc = Location(**data.model_dump())
    db.add(loc)
    db.commit()
    db.refresh(loc)
    return loc


@router.put("/locations/{loc_id}", response_model=LocationOut)
def update_location(loc_id: int, data: LocationIn, db: Session = Depends(get_db)):
    loc = db.get(Location, loc_id)
    if not loc:
        raise HTTPException(status_code=404, detail="Location not found")
    for k, v in data.model_dump().items():
        setattr(loc, k, v)
    db.commit()
    db.refresh(loc)
    return loc


@router.delete("/locations/{loc_id}")
def delete_location(loc_id: int, db: Session = Depends(get_db)):
    loc = db.get(Location, loc_id)
    if not loc:
        raise HTTPException(status_code=404, detail="Location not found")
    db.delete(loc)
    db.commit()
    return {"ok": True}


# ── Tasks ──────────────────────────────────────────────────────────────────

@router.get("/tasks", response_model=list[TaskOut])
def list_tasks(db: Session = Depends(get_db)):
    return db.query(Task).all()


@router.post("/tasks", response_model=TaskOut, status_code=201)
def create_task(data: TaskIn, db: Session = Depends(get_db)):
    task = Task(**data.model_dump())
    db.add(task)
    db.commit()
    db.refresh(task)
    return task


@router.put("/tasks/{task_id}", response_model=TaskOut)
def update_task(task_id: int, data: TaskIn, db: Session = Depends(get_db)):
    task = db.get(Task, task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    for k, v in data.model_dump().items():
        setattr(task, k, v)
    db.commit()
    db.refresh(task)
    return task


@router.delete("/tasks/{task_id}")
def delete_task(task_id: int, db: Session = Depends(get_db)):
    task = db.get(Task, task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    db.delete(task)
    db.commit()
    return {"ok": True}


# ── People ─────────────────────────────────────────────────────────────────

@router.get("/people", response_model=list[PersonOut])
def list_people(db: Session = Depends(get_db)):
    return db.query(Person).all()


@router.post("/people", response_model=PersonOut, status_code=201)
def create_person(data: PersonIn, db: Session = Depends(get_db)):
    person = Person(**data.model_dump())
    db.add(person)
    db.commit()
    db.refresh(person)
    return person


@router.put("/people/{person_id}", response_model=PersonOut)
def update_person(person_id: int, data: PersonIn, db: Session = Depends(get_db)):
    person = db.get(Person, person_id)
    if not person:
        raise HTTPException(status_code=404, detail="Person not found")
    for k, v in data.model_dump().items():
        setattr(person, k, v)
    db.commit()
    db.refresh(person)
    return person


@router.delete("/people/{person_id}")
def delete_person(person_id: int, db: Session = Depends(get_db)):
    person = db.get(Person, person_id)
    if not person:
        raise HTTPException(status_code=404, detail="Person not found")
    db.delete(person)
    db.commit()
    return {"ok": True}


# ── Availability Slots ─────────────────────────────────────────────────────

@router.post("/people/{person_id}/slots", response_model=SlotOut, status_code=201)
def add_slot(person_id: int, data: SlotIn, db: Session = Depends(get_db)):
    person = db.get(Person, person_id)
    if not person:
        raise HTTPException(status_code=404, detail="Person not found")
    slot = AvailabilitySlot(person_id=person_id, **data.model_dump())
    db.add(slot)
    db.commit()
    db.refresh(slot)
    return slot


@router.delete("/slots/{slot_id}")
def delete_slot(slot_id: int, db: Session = Depends(get_db)):
    slot = db.get(AvailabilitySlot, slot_id)
    if not slot:
        raise HTTPException(status_code=404, detail="Slot not found")
    db.delete(slot)
    db.commit()
    return {"ok": True}


# ── Timetable ──────────────────────────────────────────────────────────────

@router.get("/timetable", response_model=list[TimetableEntryOut])
def get_timetable(db: Session = Depends(get_db)):
    entries = db.query(TimetableEntry).order_by(
        TimetableEntry.date, TimetableEntry.start_time
    ).all()
    return [_entry_out(e) for e in entries]


@router.post("/timetable/generate", response_model=list[TimetableEntryOut])
def generate_timetable(db: Session = Depends(get_db)):
    # Remove all non-manual entries
    db.query(TimetableEntry).filter(TimetableEntry.is_manual == False).delete()
    db.commit()
    entries = sched.generate_timetable(db)
    # Re-query with ordering so relationships are loaded
    result = db.query(TimetableEntry).order_by(
        TimetableEntry.date, TimetableEntry.start_time
    ).all()
    return [_entry_out(e) for e in result]


@router.put("/timetable/{entry_id}", response_model=TimetableEntryOut)
def patch_timetable_entry(
    entry_id: int, data: TimetableEntryPatch, db: Session = Depends(get_db)
):
    entry = db.get(TimetableEntry, entry_id)
    if not entry:
        raise HTTPException(status_code=404, detail="Entry not found")
    for k, v in data.model_dump(exclude_none=True).items():
        setattr(entry, k, v)
    entry.is_manual = True
    db.commit()
    db.refresh(entry)
    return _entry_out(entry)


@router.delete("/timetable/{entry_id}")
def delete_timetable_entry(entry_id: int, db: Session = Depends(get_db)):
    entry = db.get(TimetableEntry, entry_id)
    if not entry:
        raise HTTPException(status_code=404, detail="Entry not found")
    db.delete(entry)
    db.commit()
    return {"ok": True}


@router.delete("/timetable")
def clear_timetable(db: Session = Depends(get_db)):
    count = db.query(TimetableEntry).count()
    db.query(TimetableEntry).delete()
    db.commit()
    return {"cleared": count}
