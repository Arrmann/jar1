"""Persistent CPU-only recognizer. Raw audio stays on this computer."""
import argparse,base64,json,sys,time,traceback
from pathlib import Path

def memory_mb():
    try:
        import ctypes
        from ctypes import wintypes
        class Counters(ctypes.Structure):
            _fields_=[('cb',wintypes.DWORD),('faults',wintypes.DWORD)]+[(n,ctypes.c_size_t) for n in ['peak_ws','ws','peak_paged','paged','peak_nonpaged','nonpaged','pagefile','peak_pagefile']]
        c=Counters();c.cb=ctypes.sizeof(c)
        current=ctypes.windll.kernel32.GetCurrentProcess;current.restype=ctypes.c_void_p
        get=ctypes.windll.psapi.GetProcessMemoryInfo;get.argtypes=[ctypes.c_void_p,ctypes.POINTER(Counters),wintypes.DWORD]
        if get(current(),ctypes.byref(c),c.cb):return round(c.ws/1048576,1)
    except Exception:pass
    return None

def main():
    p=argparse.ArgumentParser();p.add_argument('--root',required=True);p.add_argument('--threads',type=int,default=2);p.add_argument('--probe',action='store_true');a=p.parse_args()
    root=Path(a.root);sys.path.insert(0,str(root/'packages'))
    import numpy as np
    import onnxruntime as ort
    import onnx_asr
    options=ort.SessionOptions();options.intra_op_num_threads=max(1,min(a.threads,4));options.inter_op_num_threads=1
    options.execution_mode=ort.ExecutionMode.ORT_SEQUENTIAL
    started=time.perf_counter()
    model=onnx_asr.load_model('gigaam-v3-rnnt',path=root/'model',quantization='int8',sess_options=options,providers=['CPUExecutionProvider'])
    if a.probe:
        model.recognize(np.zeros(8000,dtype=np.float32),sample_rate=16000)
        print(json.dumps(dict(ok=True)),flush=True);return
    print(json.dumps(dict(ready=True,load_ms=round((time.perf_counter()-started)*1000),memory_mb=memory_mb())),flush=True)
    for line in sys.stdin:
        try:
            request=json.loads(line)
            if request.get('action')=='stop':break
            rate=int(request.get('sample_rate',16000))
            raw=base64.b64decode(request['pcm'],validate=True)
            if rate!=16000 or len(raw)>16000*2*30 or len(raw)%2:raise ValueError('Expected 16 kHz mono PCM, at most 30 seconds')
            samples=np.frombuffer(raw,dtype='<i2').astype(np.float32)/32768.
            started=time.perf_counter();text=model.recognize(samples,sample_rate=rate)
            print(json.dumps(dict(text=text,elapsed_ms=round((time.perf_counter()-started)*1000),memory_mb=memory_mb()),ensure_ascii=True),flush=True)
        except Exception as error:
            print(json.dumps(dict(error=str(error))),flush=True)

if __name__=='__main__':
    try:main()
    except Exception:
        traceback.print_exc(file=sys.stderr);sys.exit(1)
