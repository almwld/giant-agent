"""Restricted local Python runner for Giant Agent.

This is a constrained scripting environment, not an OS-level security sandbox.
Only a small AST allowlist and safe built-ins are exposed.
"""
import ast
import contextlib
import io
import os
import sys
import time

MAX_CODE_BYTES = 32 * 1024
MAX_OUTPUT_CHARS = 32 * 1024
MAX_STEPS = 100000
MAX_SECONDS = 3.0
MAX_RANGE = 10000

_ALLOWED_NODES = (
    ast.Module, ast.Expr, ast.Assign, ast.AugAssign, ast.Name, ast.Load,
    ast.Store, ast.Constant, ast.List, ast.Tuple, ast.Dict, ast.Set,
    ast.BinOp, ast.UnaryOp, ast.BoolOp, ast.Compare, ast.If, ast.For,
    ast.Break, ast.Continue, ast.Pass, ast.Call, ast.Subscript, ast.Slice,
    ast.Add, ast.Sub, ast.Mult, ast.Div, ast.FloorDiv, ast.Mod,
    ast.USub, ast.UAdd, ast.Not, ast.And, ast.Or, ast.Eq, ast.NotEq,
    ast.Lt, ast.LtE, ast.Gt, ast.GtE, ast.In, ast.NotIn,
)

def _bounded_range(*args):
    values = range(*args)
    if len(values) > MAX_RANGE:
        raise ValueError("range limit exceeded (10,000 items)")
    return values

def _validate(tree):
    for node in ast.walk(tree):
        if not isinstance(node, _ALLOWED_NODES):
            raise PermissionError("Python construct is not allowed: " + type(node).__name__)
        if isinstance(node, ast.Name) and (node.id.startswith("__") or node.id in {"open", "eval", "exec", "compile", "globals", "locals", "vars", "getattr", "setattr", "delattr", "input", "help", "breakpoint", "memoryview", "type", "object", "super", "classmethod", "staticmethod"}):
            raise PermissionError("Name is not allowed: " + node.id)
        if isinstance(node, ast.Call) and not isinstance(node.func, ast.Name):
            raise PermissionError("Only direct calls to approved functions are allowed")

def run_code(code, workspace_path):
    if not isinstance(code, str) or len(code.encode("utf-8")) > MAX_CODE_BYTES:
        return {"status": "error", "output": "", "error": "Code exceeds the 32 KB limit."}
    workspace = os.path.realpath(workspace_path)
    if not os.path.isdir(workspace):
        return {"status": "error", "output": "", "error": "Workspace directory is unavailable."}

    stdout = io.StringIO()
    stderr = io.StringIO()
    safe_builtins = {
        "print": print, "range": _bounded_range, "len": len, "sum": sum,
        "min": min, "max": max, "abs": abs, "round": round,
        "enumerate": enumerate, "zip": zip, "sorted": sorted,
        "int": int, "float": float, "str": str, "bool": bool,
        "list": list, "tuple": tuple, "dict": dict, "set": set,
    }
    namespace = {"__builtins__": safe_builtins}
    started = time.monotonic()
    steps = [0]

    def guard(frame, event, arg):
        if event == "line":
            steps[0] += 1
            if steps[0] > MAX_STEPS or time.monotonic() - started > MAX_SECONDS:
                raise TimeoutError("Python execution limit exceeded.")
        return guard

    old_trace = sys.gettrace()
    try:
        tree = ast.parse(code, mode="exec")
        _validate(tree)
        compiled = compile(tree, "<giant-agent>", "exec")
        sys.settrace(guard)
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            exec(compiled, namespace, namespace)
    except BaseException as exc:
        stderr.write(type(exc).__name__ + ": " + str(exc))
    finally:
        sys.settrace(old_trace)

    output = stdout.getvalue()
    error = stderr.getvalue()
    if len(output) > MAX_OUTPUT_CHARS:
        output = output[:MAX_OUTPUT_CHARS] + "\n[output truncated]"
    if len(error) > MAX_OUTPUT_CHARS:
        error = error[:MAX_OUTPUT_CHARS] + "\n[error truncated]"
    return {"status": "error" if error else "success", "output": output, "error": error}
