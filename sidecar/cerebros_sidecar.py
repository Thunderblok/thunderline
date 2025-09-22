from fastapi import FastAPI
from pydantic import BaseModel
import numpy as np

app = FastAPI()

class GemmRequest(BaseModel):
    a: list
    b: list
    opts: dict | None = None

@app.post("/gemm_fp16_acc32")
def gemm(req: GemmRequest):
    try:
        a = np.array(req.a, dtype=np.float16)
        b = np.array(req.b, dtype=np.float16)
        # Accumulate in float32
        res = (a.astype(np.float32) @ b.astype(np.float32)).tolist()
        return {"ok": True, "result": res}
    except Exception as e:
        return {"ok": False, "error": str(e)}

# Byte-oriented endpoint (FP16 binaries) for low-copy interop
# Accepts base64-encoded FP16 row-major A (m×k) and B (k×n), returns base64 FP16 C (m×n)
from pydantic import BaseModel as _BaseModel  # reuse; alias to avoid confusion

class GemmBytesRequest(_BaseModel):
    m: int
    n: int
    k: int
    a_base64: str
    b_base64: str

@app.post("/gemm_fp16_acc32_bytes")
def gemm_bytes(req: GemmBytesRequest):
    import base64
    try:
        a = np.frombuffer(base64.b64decode(req.a_base64), dtype=np.float16).astype(np.float32).reshape((req.m, req.k))
        b = np.frombuffer(base64.b64decode(req.b_base64), dtype=np.float16).astype(np.float32).reshape((req.k, req.n))
        c = (a @ b).astype(np.float16).tobytes(order="C")
        return {"ok": True, "c_base64": base64.b64encode(c).decode("ascii")}
    except Exception as e:
        return {"ok": False, "error": str(e)}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8089)
