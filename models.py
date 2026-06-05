from sqlalchemy import Boolean, Column, Float, ForeignKey, Integer, String
from sqlalchemy.orm import relationship
from database import Base


class Location(Base):
    __tablename__ = "locations"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, nullable=False)
    address = Column(String, default="")
    description = Column(String, default="")
    capacity = Column(Integer, default=1)

    timetable_entries = relationship("TimetableEntry", back_populates="location")


class Task(Base):
    __tablename__ = "tasks"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, nullable=False)
    description = Column(String, default="")
    duration_hours = Column(Float, nullable=False)
    people_needed = Column(Integer, default=1)

    timetable_entries = relationship("TimetableEntry", back_populates="task")


class Person(Base):
    __tablename__ = "people"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, nullable=False)
    email = Column(String, default="")

    availability_slots = relationship(
        "AvailabilitySlot", back_populates="person", cascade="all, delete-orphan"
    )
    timetable_entries = relationship("TimetableEntry", back_populates="person")


class AvailabilitySlot(Base):
    __tablename__ = "availability_slots"

    id = Column(Integer, primary_key=True, index=True)
    person_id = Column(Integer, ForeignKey("people.id", ondelete="CASCADE"), nullable=False)
    date = Column(String, nullable=False)       # "YYYY-MM-DD"
    start_time = Column(String, nullable=False) # "HH:MM"
    end_time = Column(String, nullable=False)   # "HH:MM"

    person = relationship("Person", back_populates="availability_slots")


class TimetableEntry(Base):
    __tablename__ = "timetable_entries"

    id = Column(Integer, primary_key=True, index=True)
    person_id = Column(Integer, ForeignKey("people.id", ondelete="SET NULL"), nullable=True)
    task_id = Column(Integer, ForeignKey("tasks.id", ondelete="SET NULL"), nullable=True)
    location_id = Column(Integer, ForeignKey("locations.id", ondelete="SET NULL"), nullable=True)
    date = Column(String, nullable=False)
    start_time = Column(String, nullable=False)
    end_time = Column(String, nullable=False)
    is_manual = Column(Boolean, default=False)
    notes = Column(String, default="")

    person = relationship("Person", back_populates="timetable_entries")
    task = relationship("Task", back_populates="timetable_entries")
    location = relationship("Location", back_populates="timetable_entries")
