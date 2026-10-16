import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
from types import SimpleNamespace

spec = importlib.util.spec_from_file_location('experiment_observe', Path(__file__).resolve().parents[2] / 'infra/experiment/observe.py')
observe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(observe)


class ExperimentObservationTests(unittest.TestCase):
    def test_retention_failures_are_aggregate_only_and_fail_health_projection(self):
        rows={'observed_utc':'2026-10-15T00:00:00Z','capacity':{}}
        logs=[SimpleNamespace(returncode=0,stdout=b'normal\n',stderr=b''),SimpleNamespace(returncode=0,stdout=b'',stderr=b'operations_retention_failed synthetic-private-content\n')]
        with patch.object(observe,'operator',return_value=__import__('json').dumps(rows)),patch.object(observe.subprocess,'run',side_effect=logs),patch.object(observe,'atomic') as save:
            result=observe.once();self.assertEqual(result['status'],'FAIL')
            report=save.call_args.args[1];self.assertEqual(report['observation_retention_failures_last_hour'],1);self.assertEqual(report['observation_write_failures_last_hour'],0)
            self.assertNotIn('synthetic-private-content',__import__('json').dumps(report))
    def test_truncated_log_coverage_cannot_be_reported_as_healthy(self):
        with patch.object(observe,'operator',return_value='{"observed_utc":"2026-10-15T00:00:00Z","capacity":{}}'),patch.object(observe.subprocess,'run',return_value=SimpleNamespace(returncode=0,stdout=b'line\n'*20000,stderr=b'')),patch.object(observe,'atomic') as save:
            with self.assertRaisesRegex(ValueError,'LOG_COVERAGE_UNCONFIRMED'):observe.once()
            save.assert_not_called()
    def container(self, project='song-record-experiment', database='song_record_experiment', user='song_record_experiment'):
        return {'Config': {'Labels': {'com.docker.compose.project': project},
                           'Env': ['DB_NAME=' + database, 'DB_USER=' + user]},
                'State': {'Running': True}}

    def test_scope_accepts_only_the_existing_experiment(self):
        observe.verify_scope(self.container())
        for container in [self.container(project='song-record-validation'),
                          self.container(database='song_record_prod'),
                          self.container(user='root')]:
            with self.assertRaisesRegex(ValueError, '^EXPERIMENT_SCOPE_REJECTED$'):
                observe.verify_scope(container)

    def test_stopped_api_is_not_reported_as_observed(self):
        container = self.container()
        container['State']['Running'] = False
        with self.assertRaisesRegex(ValueError, '^EXPERIMENT_API_UNAVAILABLE$'):
            observe.verify_scope(container)

    def test_arbitrary_or_deletion_operator_cannot_use_this_bridge(self):
        for main in ('BackupLedgerOperator', 'RestoreValidationOperator', 'other.Main'):
            with self.assertRaisesRegex(ValueError, '^EXPERIMENT_OPERATOR_SCOPE_REJECTED$'):
                observe.operator(main)
