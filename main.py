from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from database import engine
import models
from routers import calc, planner as planner_router

models.Base.metadata.create_all(bind=engine)

app = FastAPI(title="Jump App")
app.mount("/static", StaticFiles(directory="static"), name="static")

app.include_router(calc.router)
app.include_router(planner_router.router, prefix="/api/planner")


@app.get("/")
async def root():
    return FileResponse("static/index.html")


@app.get("/planner")
async def planner_page():
    return FileResponse("static/planner.html")
