"""Bounded serialization of backup and restore with the existing ledger lock."""
from contextlib import contextmanager
import time


@contextmanager
def execution_lock(path, timeout=60):
    import fcntl
    if timeout <= 0 or timeout > 120:
        raise ValueError('INVALID_EXECUTION_LOCK_TIMEOUT')
    with path.open('a+b') as lock:
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError('EXPERIMENT_EXECUTION_LOCK_TIMEOUT') from None
                time.sleep(min(0.1, remaining))
        try:
            yield lock
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)
