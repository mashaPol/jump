"use strict";

const state = { locations: [], tasks: [], people: [], timetable: [] };

// ── API helper ─────────────────────────────────────────────────────────────

async function apiFetch(method, path, body) {
  const opts = {
    method,
    headers: body ? { "Content-Type": "application/json" } : {},
    body: body ? JSON.stringify(body) : undefined,
  };
  const res = await fetch("/api/planner" + path, opts);
  if (!res.ok) {
    const err = await res.json().catch(() => ({ detail: res.statusText }));
    throw new Error(err.detail || res.statusText);
  }
  if (res.status === 204) return null;
  return res.json();
}

// ── Toast ──────────────────────────────────────────────────────────────────

let toastTimer;
function showToast(msg) {
  const el = document.getElementById("toast");
  el.textContent = msg;
  el.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove("show"), 3500);
}

// ── Loaders ────────────────────────────────────────────────────────────────

async function loadAll() {
  const [locs, tasks, people, timetable] = await Promise.all([
    apiFetch("GET", "/locations"),
    apiFetch("GET", "/tasks"),
    apiFetch("GET", "/people"),
    apiFetch("GET", "/timetable"),
  ]);
  state.locations = locs;
  state.tasks = tasks;
  state.people = people;
  state.timetable = timetable;
}

// ── Render: Locations ──────────────────────────────────────────────────────

function renderLocations() {
  const el = document.getElementById("locations-list");
  if (!state.locations.length) {
    el.innerHTML = '<p class="empty-state"><strong>No locations yet.</strong>Add one above.</p>';
    return;
  }
  el.innerHTML = state.locations.map(loc => `
    <div class="entity-card" id="loc-card-${loc.id}">
      <div class="card-header">
        <span class="card-name">${esc(loc.name)}</span>
        <button class="btn-icon" onclick="startEditLocation(${loc.id})" title="Edit">✏️</button>
        <button class="btn-icon delete" onclick="deleteLocation(${loc.id})" title="Delete">🗑️</button>
      </div>
      <div class="card-meta">
        ${loc.address ? `<span>📍 ${esc(loc.address)}</span>` : ""}
        ${loc.description ? `<span>${esc(loc.description)}</span>` : ""}
        <span>Capacity: ${loc.capacity}</span>
      </div>
    </div>
  `).join("");
}

function startEditLocation(id) {
  const loc = state.locations.find(l => l.id === id);
  const card = document.getElementById(`loc-card-${id}`);
  card.innerHTML = `
    <div class="card-edit-row">
      <input data-field="name" value="${esc(loc.name)}" placeholder="Name" />
      <input data-field="address" value="${esc(loc.address)}" placeholder="Address" />
      <input data-field="description" value="${esc(loc.description)}" placeholder="Description" />
      <input data-field="capacity" type="number" min="1" value="${loc.capacity}" style="max-width:80px" />
      <button class="btn-icon save" onclick="saveLocation(${id})" title="Save">✔</button>
      <button class="btn-icon cancel" onclick="renderLocations()" title="Cancel">✖</button>
    </div>`;
}

async function saveLocation(id) {
  const card = document.getElementById(`loc-card-${id}`);
  const inputs = card.querySelectorAll("[data-field]");
  const data = {};
  inputs.forEach(i => data[i.dataset.field] = i.type === "number" ? Number(i.value) : i.value);
  try {
    const updated = await apiFetch("PUT", `/locations/${id}`, data);
    state.locations = state.locations.map(l => l.id === id ? updated : l);
    renderLocations();
  } catch (e) { showToast(e.message); }
}

async function deleteLocation(id) {
  if (!confirm("Delete this location?")) return;
  try {
    await apiFetch("DELETE", `/locations/${id}`);
    state.locations = state.locations.filter(l => l.id !== id);
    renderLocations();
    renderTimetable();
  } catch (e) { showToast(e.message); }
}

// ── Render: Tasks ──────────────────────────────────────────────────────────

function renderTasks() {
  const el = document.getElementById("tasks-list");
  if (!state.tasks.length) {
    el.innerHTML = '<p class="empty-state"><strong>No tasks yet.</strong>Add one above.</p>';
    return;
  }
  el.innerHTML = state.tasks.map(t => `
    <div class="entity-card" id="task-card-${t.id}">
      <div class="card-header">
        <span class="card-name">${esc(t.name)}</span>
        <button class="btn-icon" onclick="startEditTask(${t.id})" title="Edit">✏️</button>
        <button class="btn-icon delete" onclick="deleteTask(${t.id})" title="Delete">🗑️</button>
      </div>
      <div class="card-meta">
        ${t.description ? `<span>${esc(t.description)}</span>` : ""}
        <span>⏱ ${t.duration_hours}h</span>
        <span>👥 ${t.people_needed} person${t.people_needed !== 1 ? "s" : ""}</span>
      </div>
    </div>
  `).join("");
}

function startEditTask(id) {
  const t = state.tasks.find(x => x.id === id);
  const card = document.getElementById(`task-card-${id}`);
  card.innerHTML = `
    <div class="card-edit-row">
      <input data-field="name" value="${esc(t.name)}" placeholder="Name" />
      <input data-field="description" value="${esc(t.description)}" placeholder="Description" />
      <input data-field="duration_hours" type="number" min="0.25" step="0.25" value="${t.duration_hours}" style="max-width:90px" placeholder="Hours" />
      <input data-field="people_needed" type="number" min="1" value="${t.people_needed}" style="max-width:80px" />
      <button class="btn-icon save" onclick="saveTask(${id})">✔</button>
      <button class="btn-icon cancel" onclick="renderTasks()">✖</button>
    </div>`;
}

async function saveTask(id) {
  const card = document.getElementById(`task-card-${id}`);
  const inputs = card.querySelectorAll("[data-field]");
  const data = {};
  inputs.forEach(i => data[i.dataset.field] = i.type === "number" ? Number(i.value) : i.value);
  try {
    const updated = await apiFetch("PUT", `/tasks/${id}`, data);
    state.tasks = state.tasks.map(t => t.id === id ? updated : t);
    renderTasks();
  } catch (e) { showToast(e.message); }
}

async function deleteTask(id) {
  if (!confirm("Delete this task?")) return;
  try {
    await apiFetch("DELETE", `/tasks/${id}`);
    state.tasks = state.tasks.filter(t => t.id !== id);
    renderTasks();
    renderTimetable();
  } catch (e) { showToast(e.message); }
}

// ── Render: People ─────────────────────────────────────────────────────────

function renderPeople() {
  const el = document.getElementById("people-list");
  if (!state.people.length) {
    el.innerHTML = '<p class="empty-state"><strong>No people yet.</strong>Add one above.</p>';
    return;
  }
  el.innerHTML = state.people.map(p => `
    <div class="entity-card" id="person-card-${p.id}">
      <div class="card-header">
        <span class="card-name">${esc(p.name)}</span>
        <button class="btn-icon" onclick="startEditPerson(${p.id})" title="Edit">✏️</button>
        <button class="btn-icon delete" onclick="deletePerson(${p.id})" title="Delete">🗑️</button>
      </div>
      <div class="card-meta">
        ${p.email ? `<span>✉️ ${esc(p.email)}</span>` : ""}
        <span>${p.availability_slots.length} availability slot${p.availability_slots.length !== 1 ? "s" : ""}</span>
      </div>
      <div class="slots-section">
        <button class="slots-toggle" onclick="toggleSlots(${p.id})">
          <span id="slots-arrow-${p.id}">▶</span> Availability slots
        </button>
        <div class="slots-body" id="slots-body-${p.id}">
          <div class="slot-add-form">
            <input type="date" id="slot-date-${p.id}" />
            <input type="time" id="slot-start-${p.id}" />
            <input type="time" id="slot-end-${p.id}" />
            <button class="btn-primary" style="padding:6px 14px;font-size:0.82rem" onclick="addSlot(${p.id})">+ Add</button>
          </div>
          <div class="slot-list" id="slot-list-${p.id}">
            ${renderSlotRows(p)}
          </div>
        </div>
      </div>
    </div>
  `).join("");
}

function renderSlotRows(p) {
  if (!p.availability_slots.length) return '<p style="color:#8b949e;font-size:0.82rem;margin:0">No slots yet.</p>';
  return p.availability_slots.map(s => `
    <div class="slot-row">
      <span class="slot-text">📅 ${s.date} &nbsp; ${s.start_time} – ${s.end_time}</span>
      <button class="btn-icon delete" onclick="deleteSlot(${p.id}, ${s.id})" title="Remove">✖</button>
    </div>
  `).join("");
}

function toggleSlots(personId) {
  const body = document.getElementById(`slots-body-${personId}`);
  const arrow = document.getElementById(`slots-arrow-${personId}`);
  body.classList.toggle("open");
  arrow.textContent = body.classList.contains("open") ? "▼" : "▶";
}

async function addSlot(personId) {
  const date = document.getElementById(`slot-date-${personId}`).value;
  const start = document.getElementById(`slot-start-${personId}`).value;
  const end = document.getElementById(`slot-end-${personId}`).value;
  if (!date || !start || !end) { showToast("Fill in date, start and end time."); return; }
  if (start >= end) { showToast("Start time must be before end time."); return; }
  try {
    const slot = await apiFetch("POST", `/people/${personId}/slots`, { date, start_time: start, end_time: end });
    const p = state.people.find(x => x.id === personId);
    p.availability_slots.push(slot);
    document.getElementById(`slot-list-${personId}`).innerHTML = renderSlotRows(p);
    const meta = document.querySelector(`#person-card-${personId} .card-meta`);
    if (meta) {
      const countSpan = meta.querySelector("span:last-child");
      if (countSpan) countSpan.textContent = `${p.availability_slots.length} availability slot${p.availability_slots.length !== 1 ? "s" : ""}`;
    }
  } catch (e) { showToast(e.message); }
}

async function deleteSlot(personId, slotId) {
  try {
    await apiFetch("DELETE", `/slots/${slotId}`);
    const p = state.people.find(x => x.id === personId);
    p.availability_slots = p.availability_slots.filter(s => s.id !== slotId);
    document.getElementById(`slot-list-${personId}`).innerHTML = renderSlotRows(p);
  } catch (e) { showToast(e.message); }
}

function startEditPerson(id) {
  const p = state.people.find(x => x.id === id);
  const card = document.getElementById(`person-card-${id}`);
  // preserve slots section by only replacing top part
  card.innerHTML = `
    <div class="card-edit-row">
      <input data-field="name" value="${esc(p.name)}" placeholder="Name" />
      <input data-field="email" value="${esc(p.email)}" placeholder="Email" />
      <button class="btn-icon save" onclick="savePerson(${id})">✔</button>
      <button class="btn-icon cancel" onclick="renderPeople()">✖</button>
    </div>`;
}

async function savePerson(id) {
  const card = document.getElementById(`person-card-${id}`);
  const inputs = card.querySelectorAll("[data-field]");
  const data = {};
  inputs.forEach(i => data[i.dataset.field] = i.value);
  try {
    const updated = await apiFetch("PUT", `/people/${id}`, data);
    updated.availability_slots = state.people.find(p => p.id === id).availability_slots;
    state.people = state.people.map(p => p.id === id ? updated : p);
    renderPeople();
  } catch (e) { showToast(e.message); }
}

async function deletePerson(id) {
  if (!confirm("Delete this person and all their availability slots?")) return;
  try {
    await apiFetch("DELETE", `/people/${id}`);
    state.people = state.people.filter(p => p.id !== id);
    renderPeople();
    renderTimetable();
  } catch (e) { showToast(e.message); }
}

// ── Render: Timetable ──────────────────────────────────────────────────────

function renderTimetable() {
  const el = document.getElementById("timetable-container");
  if (!state.timetable.length) {
    el.innerHTML = `<div class="empty-state">
      <strong>No timetable yet.</strong>
      Add locations, tasks, and people with availability slots,<br>then click <em>Generate Timetable</em>.
    </div>`;
    return;
  }

  const rows = state.timetable.map(e => `
    <tr class="${e.is_manual ? "row-manual" : ""}" id="te-row-${e.id}">
      <td>${esc(e.date)}</td>
      <td>${esc(e.start_time)} – ${esc(e.end_time)}</td>
      <td>${esc(e.task_name || "—")}${e.is_manual ? '<span class="badge-manual">edited</span>' : ""}</td>
      <td>${esc(e.person_name || "—")}</td>
      <td>${esc(e.location_name || "—")}</td>
      <td style="max-width:160px;color:#8b949e;font-size:0.82rem">${esc(e.notes || "")}</td>
      <td>
        <button class="btn-icon" onclick="startEditEntry(${e.id})" title="Edit">✏️</button>
        <button class="btn-icon delete" onclick="deleteEntry(${e.id})" title="Delete">🗑️</button>
      </td>
    </tr>
  `).join("");

  el.innerHTML = `
    <table class="timetable-table">
      <thead>
        <tr>
          <th>Date</th><th>Time</th><th>Task</th><th>Person</th><th>Location</th><th>Notes</th><th></th>
        </tr>
      </thead>
      <tbody>${rows}</tbody>
    </table>`;
}

function startEditEntry(id) {
  const e = state.timetable.find(x => x.id === id);
  const row = document.getElementById(`te-row-${id}`);

  const personOpts = state.people.map(p =>
    `<option value="${p.id}" ${p.id === e.person_id ? "selected" : ""}>${esc(p.name)}</option>`
  ).join("");
  const taskOpts = state.tasks.map(t =>
    `<option value="${t.id}" ${t.id === e.task_id ? "selected" : ""}>${esc(t.name)}</option>`
  ).join("");
  const locOpts = state.locations.map(l =>
    `<option value="${l.id}" ${l.id === e.location_id ? "selected" : ""}>${esc(l.name)}</option>`
  ).join("");

  row.innerHTML = `
    <td><input data-field="date" type="date" value="${e.date}" /></td>
    <td style="white-space:nowrap">
      <input data-field="start_time" type="time" value="${e.start_time}" style="min-width:80px" />
      –
      <input data-field="end_time" type="time" value="${e.end_time}" style="min-width:80px" />
    </td>
    <td><select data-field="task_id">${taskOpts}</select></td>
    <td><select data-field="person_id">${personOpts}</select></td>
    <td><select data-field="location_id">${locOpts}</select></td>
    <td><input data-field="notes" value="${esc(e.notes || "")}" placeholder="Notes" /></td>
    <td>
      <button class="btn-icon save" onclick="saveEntry(${id})">✔</button>
      <button class="btn-icon cancel" onclick="renderTimetable()">✖</button>
    </td>`;
}

async function saveEntry(id) {
  const row = document.getElementById(`te-row-${id}`);
  const inputs = row.querySelectorAll("[data-field]");
  const patch = { is_manual: true };
  inputs.forEach(i => {
    patch[i.dataset.field] = (i.dataset.field === "person_id" || i.dataset.field === "task_id" || i.dataset.field === "location_id")
      ? (i.value ? Number(i.value) : null)
      : i.value;
  });
  try {
    const updated = await apiFetch("PUT", `/timetable/${id}`, patch);
    state.timetable = state.timetable.map(e => e.id === id ? updated : e);
    renderTimetable();
  } catch (e) { showToast(e.message); }
}

async function deleteEntry(id) {
  try {
    await apiFetch("DELETE", `/timetable/${id}`);
    state.timetable = state.timetable.filter(e => e.id !== id);
    renderTimetable();
  } catch (e) { showToast(e.message); }
}

// ── Timetable generate / clear ─────────────────────────────────────────────

async function generateTimetable() {
  const btn = document.getElementById("btn-generate");
  btn.disabled = true;
  btn.textContent = "Generating…";
  try {
    state.timetable = await apiFetch("POST", "/timetable/generate");
    renderTimetable();
  } catch (e) {
    showToast(e.message);
  } finally {
    btn.disabled = false;
    btn.textContent = "Generate Timetable";
  }
}

async function clearTimetable() {
  if (!confirm("Clear all timetable entries?")) return;
  try {
    await apiFetch("DELETE", "/timetable");
    state.timetable = [];
    renderTimetable();
  } catch (e) { showToast(e.message); }
}

// ── Tab switching ──────────────────────────────────────────────────────────

function switchTab(name) {
  document.querySelectorAll(".tab-panel").forEach(p => p.classList.remove("active"));
  document.querySelectorAll(".tab-bar button").forEach(b => b.classList.remove("active"));
  document.getElementById(`tab-${name}`).classList.add("active");
  document.querySelector(`[data-tab="${name}"]`).classList.add("active");
}

// ── Form handlers ──────────────────────────────────────────────────────────

document.getElementById("location-form").addEventListener("submit", async e => {
  e.preventDefault();
  const fd = new FormData(e.target);
  const data = {
    name: fd.get("name"),
    address: fd.get("address") || "",
    description: fd.get("description") || "",
    capacity: Number(fd.get("capacity")) || 1,
  };
  try {
    const loc = await apiFetch("POST", "/locations", data);
    state.locations.push(loc);
    renderLocations();
    e.target.reset();
    document.getElementById("loc-cap").value = "1";
  } catch (err) { showToast(err.message); }
});

document.getElementById("task-form").addEventListener("submit", async e => {
  e.preventDefault();
  const fd = new FormData(e.target);
  const data = {
    name: fd.get("name"),
    description: fd.get("description") || "",
    duration_hours: Number(fd.get("duration_hours")),
    people_needed: Number(fd.get("people_needed")) || 1,
  };
  try {
    const task = await apiFetch("POST", "/tasks", data);
    state.tasks.push(task);
    renderTasks();
    e.target.reset();
    document.getElementById("task-ppl").value = "1";
  } catch (err) { showToast(err.message); }
});

document.getElementById("person-form").addEventListener("submit", async e => {
  e.preventDefault();
  const fd = new FormData(e.target);
  const data = { name: fd.get("name"), email: fd.get("email") || "" };
  try {
    const person = await apiFetch("POST", "/people", data);
    person.availability_slots = [];
    state.people.push(person);
    renderPeople();
    e.target.reset();
  } catch (err) { showToast(err.message); }
});

document.getElementById("btn-generate").addEventListener("click", generateTimetable);
document.getElementById("btn-clear-all").addEventListener("click", clearTimetable);

document.querySelectorAll(".tab-bar button").forEach(btn => {
  btn.addEventListener("click", () => switchTab(btn.dataset.tab));
});

// ── Utility ────────────────────────────────────────────────────────────────

function esc(str) {
  return String(str ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

// ── Init ───────────────────────────────────────────────────────────────────

(async () => {
  await loadAll();
  renderLocations();
  renderTasks();
  renderPeople();
  renderTimetable();
})();
