"""Restricted local Python runner. This is defense in depth, not an OS sandbox."""
import ast
import contextlib
import io
import sys
import re
from collections import OrderedDict
import time

MAX_CODE_BYTES = 32 * 1024
MAX_OUTPUT_CHARS = 32 * 1024
MAX_STEPS = 50000
MAX_SECONDS = 2.5
MAX_RANGE = 5000
MAX_LITERAL_STRING = 8192
MAX_LITERAL_ITEMS = 1000
MAX_INTEGER_BITS = 256


class BoundedOutput(io.TextIOBase):
    def __init__(self, limit):
        self.limit = limit
        self.parts = []
        self.length = 0
        self.truncated = False

    def write(self, value):
        value = str(value)
        remaining = self.limit - self.length
        if remaining > 0:
            piece = value[:remaining]
            self.parts.append(piece)
            self.length += len(piece)
        if len(value) > remaining:
            self.truncated = True
        return len(value)

    def getvalue(self):
        value = "".join(self.parts)
        return value + ("\\n[output truncated]" if self.truncated else "")


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
        raise ValueError("range limit exceeded (5,000 items)")
    return values


def _validate(tree):
    for node in ast.walk(tree):
        if not isinstance(node, _ALLOWED_NODES):
            raise PermissionError("Python construct is not allowed: " + type(node).__name__)
        if isinstance(node, ast.Constant):
            value = node.value
            if isinstance(value, str) and len(value) > MAX_LITERAL_STRING:
                raise ValueError("String literal exceeds 8 KB.")
            if isinstance(value, (int, float)) and not isinstance(value, bool):
                if isinstance(value, int) and value.bit_length() > MAX_INTEGER_BITS:
                    raise ValueError("Integer literal is too large.")
                if isinstance(value, float) and (value != value or abs(value) > 1e100):
                    raise ValueError("Non-finite or oversized float literal.")
        if isinstance(node, (ast.List, ast.Tuple, ast.Set)) and len(node.elts) > MAX_LITERAL_ITEMS:
            raise ValueError("Collection literal exceeds 1,000 items.")
        if isinstance(node, ast.Dict) and len(node.keys) > MAX_LITERAL_ITEMS:
            raise ValueError("Dictionary literal exceeds 1,000 items.")
        if isinstance(node, ast.Name) and (
            node.id.startswith("__") or node.id in {
                "open", "eval", "exec", "compile", "globals", "locals", "vars",
                "getattr", "setattr", "delattr", "input", "help", "breakpoint",
                "memoryview", "type", "object", "super", "classmethod", "staticmethod",
            }
        ):
            raise PermissionError("Name is not allowed: " + node.id)
        if isinstance(node, ast.Call) and not isinstance(node.func, ast.Name):
            raise PermissionError("Only direct calls to approved functions are allowed")


def _safe_builtins():
    return {
        "print": print, "range": _bounded_range, "len": len, "sum": sum,
        "min": min, "max": max, "abs": abs, "round": round,
        "enumerate": enumerate, "zip": zip, "sorted": sorted,
        "int": int, "float": float, "str": str, "bool": bool,
        "list": list, "tuple": tuple, "dict": dict, "set": set,
    }


def _run_with_namespace(code, workspace_path, namespace=None):
    if not isinstance(code, str) or len(code.encode("utf-8")) > MAX_CODE_BYTES:
        return {"status": "error", "output": "", "error": "Code exceeds the 32 KB limit."}

    stdout = BoundedOutput(MAX_OUTPUT_CHARS)
    stderr = BoundedOutput(MAX_OUTPUT_CHARS)
    if namespace is None:
        namespace = {"__builtins__": _safe_builtins()}
    else:
        namespace.setdefault("__builtins__", _safe_builtins())
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
    return {"status": "error" if error else "success", "output": output, "error": error}


def run_code(code, workspace_path):
    """One-shot sandbox execution with a fresh namespace for every call."""
    return _run_with_namespace(code, workspace_path)


MAX_REPL_SESSIONS = 4
MAX_REPL_VARIABLES = 256
REPL_IDLE_SECONDS = 3600
_REPL_SESSIONS = OrderedDict()


def _prune_repl_sessions(now):
    expired = [
        session_id for session_id, session in _REPL_SESSIONS.items()
        if now - session["last_used"] > REPL_IDLE_SECONDS
    ]
    for session_id in expired:
        _REPL_SESSIONS.pop(session_id, None)
    while len(_REPL_SESSIONS) > MAX_REPL_SESSIONS:
        _REPL_SESSIONS.popitem(last=False)


def run_repl(code, workspace_path, session_id):
    """Persistent, conversation-scoped REPL using the same restricted AST sandbox."""
    if not isinstance(session_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", session_id):
        return {"status": "error", "output": "", "error": "Invalid REPL session id."}
    now = time.monotonic()
    _prune_repl_sessions(now)
    session = _REPL_SESSIONS.get(session_id)
    if session is None:
        session = {
            "namespace": {"__builtins__": _safe_builtins()},
            "last_used": now,
        }
        _REPL_SESSIONS[session_id] = session
    _REPL_SESSIONS.move_to_end(session_id)
    _prune_repl_sessions(now)
    session["last_used"] = now
    result = _run_with_namespace(code, workspace_path, session["namespace"])
    namespace = session["namespace"]
    if len(namespace) > MAX_REPL_VARIABLES:
        _REPL_SESSIONS.pop(session_id, None)
        return {
            "status": "error",
            "output": result.get("output", ""),
            "error": "REPL variable limit exceeded; this session was reset.",
        }
    session["last_used"] = time.monotonic()
    return result


def reset_repl(session_id):
    if not isinstance(session_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", session_id):
        return {"ok": False, "error": "Invalid REPL session id."}
    removed = _REPL_SESSIONS.pop(session_id, None) is not None
    return {"ok": True, "reset": removed}
