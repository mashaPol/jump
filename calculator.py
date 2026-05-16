import ast
from typing import Union

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

app = FastAPI(title="Calculator API")
app.mount("/static", StaticFiles(directory="static"), name="static")


@app.get("/")
async def read_index():
    return FileResponse("static/index.html")


class ExpressionRequest(BaseModel):
    expression: str


def _evaluate(node: ast.AST) -> Union[int, float]:
    if isinstance(node, ast.BinOp):
        left = _evaluate(node.left)
        right = _evaluate(node.right)

        if isinstance(node.op, ast.Add):
            return left + right
        if isinstance(node.op, ast.Sub):
            return left - right
        if isinstance(node.op, ast.Mult):
            return left * right
        if isinstance(node.op, ast.Div):
            return left / right
        if isinstance(node.op, ast.Mod):
            return left % right
        if isinstance(node.op, ast.Pow):
            return left ** right
        if isinstance(node.op, ast.FloorDiv):
            return left // right

        raise ValueError("Unsupported binary operation")

    if isinstance(node, ast.UnaryOp):
        operand = _evaluate(node.operand)
        if isinstance(node.op, ast.UAdd):
            return +operand
        if isinstance(node.op, ast.USub):
            return -operand
        raise ValueError("Unsupported unary operation")

    if isinstance(node, ast.Constant):
        if isinstance(node.value, (int, float)):
            return node.value
        raise ValueError("Only numeric values are allowed")

    if isinstance(node, ast.Num):
        return node.n

    raise ValueError("Unsupported expression")


def safe_eval(expression: str) -> Union[int, float]:
    expression = expression.strip()
    if not expression:
        raise ValueError("Expression must not be empty")

    try:
        tree = ast.parse(expression, mode="eval")
    except SyntaxError as exc:
        raise ValueError("Invalid expression") from exc

    return _evaluate(tree.body)


@app.post("/api/calc")
async def calculate(payload: ExpressionRequest):
    try:
        result = safe_eval(payload.expression)
    except (ValueError, TypeError, ZeroDivisionError) as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    return {"expression": payload.expression, "result": result}
