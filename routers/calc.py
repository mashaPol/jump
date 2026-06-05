from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from calculator import safe_eval

router = APIRouter()


class ExpressionRequest(BaseModel):
    expression: str


@router.post("/api/calc")
async def calculate(payload: ExpressionRequest):
    try:
        result = safe_eval(payload.expression)
    except (ValueError, TypeError, ZeroDivisionError) as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    return {"expression": payload.expression, "result": result}
