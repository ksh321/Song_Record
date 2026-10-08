"""OS-enforced memory boundary for a decoder; emits only decoder stdout, never stderr."""
import os
import subprocess
import sys
import threading

# Initial per-validation native-process budget. Not an optional bypass/configuration knob.
MEMORY=512*1024*1024
JOB=None

def constrain():
    global JOB
    if os.name=='nt':
        import ctypes as c
        from ctypes import wintypes as w
        class Basic(c.Structure):
            _fields_=[('process_time',c.c_longlong),('job_time',c.c_longlong),('flags',w.DWORD),('min_working',c.c_size_t),('max_working',c.c_size_t),('active',w.DWORD),('affinity',c.c_size_t),('priority',w.DWORD),('scheduling',w.DWORD)]
        class Counters(c.Structure):
            _fields_=[(name,c.c_ulonglong) for name in ('read_ops','write_ops','other_ops','read_bytes','write_bytes','other_bytes')]
        class Extended(c.Structure):
            _fields_=[('basic',Basic),('io',Counters),('process_memory',c.c_size_t),('job_memory',c.c_size_t),('peak_process',c.c_size_t),('peak_job',c.c_size_t)]
        kernel=c.WinDLL('kernel32',use_last_error=True)
        kernel.CreateJobObjectW.argtypes=[c.c_void_p,w.LPCWSTR];kernel.CreateJobObjectW.restype=w.HANDLE
        kernel.SetInformationJobObject.argtypes=[w.HANDLE,c.c_int,c.c_void_p,w.DWORD];kernel.SetInformationJobObject.restype=w.BOOL
        kernel.AssignProcessToJobObject.argtypes=[w.HANDLE,w.HANDLE];kernel.AssignProcessToJobObject.restype=w.BOOL
        kernel.GetCurrentProcess.restype=w.HANDLE
        JOB=kernel.CreateJobObjectW(None,None)
        limit=Extended();limit.basic.flags=0x2000|0x100|0x200;limit.process_memory=MEMORY;limit.job_memory=MEMORY
        if not JOB or not kernel.SetInformationJobObject(JOB,9,c.byref(limit),c.sizeof(limit)) or not kernel.AssignProcessToJobObject(JOB,kernel.GetCurrentProcess()):raise RuntimeError()
        # Keep the non-inheritable job handle until process exit. Children join before executing.
    elif sys.platform.startswith('linux'):
        import resource
        resource.setrlimit(resource.RLIMIT_AS,(MEMORY,MEMORY))
        resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    else:raise RuntimeError()

def main():
    try:constrain()
    except Exception:return 125
    if len(sys.argv)<2:return 125
    memory_error=False
    def discard(stream):
        nonlocal memory_error
        tail=b''
        try:
            while True:
                chunk=stream.read(4096)
                if not chunk:break
                value=(tail+chunk).lower()
                if any(message in value for message in (b'cannot allocate memory',b'out of memory',b'memory allocation failed',b'memoryerror',b'failed to reallocate')):memory_error=True
                tail=value[-64:]
        finally:stream.close()
    try:
        # No shell; the decoder gets no interactive stdin. Output limits and the shared deadline are enforced by Java.
        child=subprocess.Popen(sys.argv[1:],stdin=subprocess.DEVNULL,stderr=subprocess.PIPE)
        reader=threading.Thread(target=discard,args=(child.stderr,),daemon=True);reader.start()
        code=child.wait();reader.join()
        if memory_error or code in (-9,137,0xC0000017,0xC000012D):return 124
        return 0 if code==0 else 1
    except MemoryError:return 124
    except FileNotFoundError:return 126
    except Exception:return 125

if __name__=='__main__':sys.exit(main())
