import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('experiment_execution_lock', ROOT/'infra/experiment/execution_lock.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ExecutionLockTests(unittest.TestCase):
    def test_contention_waits_and_enters_only_after_exclusive_acquisition(self):
        calls = Mock(side_effect=[BlockingIOError(), None, None])
        fake = SimpleNamespace(flock=calls, LOCK_EX=2, LOCK_NB=4, LOCK_UN=8)
        with tempfile.TemporaryDirectory() as folder, patch.dict(sys.modules, {'fcntl':fake}), patch.object(module.time,'sleep') as sleep:
            with module.execution_lock(Path(folder)/'execution.lock'):
                self.assertEqual(calls.call_count, 2)
            self.assertEqual(calls.call_count, 3)
            self.assertEqual(calls.call_args.args[1], fake.LOCK_UN)
            sleep.assert_called_once()

    def test_timeout_never_enters_protected_region(self):
        fake = SimpleNamespace(flock=Mock(side_effect=BlockingIOError()), LOCK_EX=2, LOCK_NB=4, LOCK_UN=8)
        with tempfile.TemporaryDirectory() as folder, patch.dict(sys.modules, {'fcntl':fake}), patch.object(module.time,'monotonic',side_effect=[0,61]), patch.object(module.time,'sleep') as sleep:
            with self.assertRaisesRegex(TimeoutError, 'EXPERIMENT_EXECUTION_LOCK_TIMEOUT'):
                with module.execution_lock(Path(folder)/'execution.lock'):
                    self.fail('Must not enter without a lock')
            self.assertEqual(fake.flock.call_count,1)
            sleep.assert_not_called()

    def test_protected_failure_releases_lock(self):
        fake = SimpleNamespace(flock=Mock(), LOCK_EX=2, LOCK_NB=4, LOCK_UN=8)
        with tempfile.TemporaryDirectory() as folder, patch.dict(sys.modules, {'fcntl':fake}):
            with self.assertRaisesRegex(ValueError,'synthetic failure'):
                with module.execution_lock(Path(folder)/'execution.lock'):
                    raise ValueError('synthetic failure')
            self.assertEqual(fake.flock.call_args.args[1],fake.LOCK_UN)


if __name__ == '__main__':
    unittest.main()
