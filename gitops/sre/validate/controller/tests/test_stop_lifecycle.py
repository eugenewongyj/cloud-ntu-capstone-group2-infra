import unittest
from unittest.mock import Mock
from copy import deepcopy

from lifecycle import AssessmentLifecycle
from state import initial_state, StateConflict


RUN_ID = "a" * 32


class StopLifecycleTests(unittest.TestCase):

    def setUp(self):

        self.store = Mock()
        self.executor = Mock()
        self.telemetry = Mock()

        self.state = initial_state()

        self.state.update({
            "state": "running",
            "assessment_run": RUN_ID,
            "profile": "1111",
            "repeat": True,
            "cycle": 1,
            "latest_metrics": {
                "p95_ms": 100,
            },
        })

        self.version = 100

        self.store.read.side_effect = (
            lambda: (
                deepcopy(self.state),
                str(self.version)
            )
        )

        self.store.write.side_effect = self.persist

        self.executor.status.return_value = {
            "state": "running",
            "assessment_run": RUN_ID,
        }

        self.lifecycle = AssessmentLifecycle(
            self.store,
            self.executor,
            self.telemetry,
        )

    def persist(self, state, version):

        self.assertEqual(version, str(self.version))

        self.state = deepcopy(state)
        self.version += 1

        return str(self.version)

    def test_stop_disables_repeat(self):

        result = self.lifecycle.request_stop(RUN_ID)

        self.assertEqual(result["state"], "stopping")
        self.assertTrue(result["stop_requested"])
        self.assertFalse(result["repeat"])

    def test_stop_preserves_existing_metrics(self):

        result = self.lifecycle.request_stop(RUN_ID)

        self.assertEqual(
            result["latest_metrics"]["p95_ms"], 100
        )

    def test_wrong_run_id_is_rejected(self):

        with self.assertRaises(StateConflict):
            self.lifecycle.request_stop("b" * 32)

        self.executor.stop.assert_not_called()

    def test_stop_request_is_idempotent(self):

        self.lifecycle.request_stop(RUN_ID)
        version = self.version

        self.lifecycle.request_stop(RUN_ID)

        self.assertEqual(self.version, version)

    def test_owned_job_is_terminated(self):

        self.lifecycle.request_stop(RUN_ID)

        self.lifecycle.reconcile_stop(now=1000)

        self.executor.stop.assert_called_once_with(RUN_ID)

    def test_wait_for_foreground_deletion(self):

        self.lifecycle.request_stop(RUN_ID)

        self.executor.status.return_value["state"] = "stopping"

        result = self.lifecycle.reconcile_stop(now=1000)

        self.assertEqual(result["state"], "stopping")
        self.executor.stop.assert_not_called()

    def test_missing_job_completes_stop(self):

        self.lifecycle.request_stop(RUN_ID)

        self.executor.status.return_value = {
            "state": "idle"
        }

        result = self.lifecycle.reconcile_stop(now=1000)

        self.assertEqual(result["state"], "stopped")
        self.assertEqual(result["stopped_at"], 1000)
        self.assertFalse(result["repeat"])

    def test_unrelated_job_is_not_deleted(self):

        self.lifecycle.request_stop(RUN_ID)

        self.executor.status.return_value[
            "assessment_run"
        ] = "b" * 32

        result = self.lifecycle.reconcile_stop(now=1000)

        self.assertEqual(result["state"], "blocked")
        self.executor.stop.assert_not_called()

    def test_stopped_is_not_recovered(self):

        self.lifecycle.request_stop(RUN_ID)

        self.executor.status.return_value = {
            "state": "idle"
        }

        result = self.lifecycle.reconcile_stop(now=1000)

        self.assertEqual(
            result["recovery_outcome"], "unconfirmed"
        )

    def test_stop_during_starting(self):

        self.state["state"] = "starting"

        self.lifecycle.request_stop(RUN_ID)

        self.lifecycle.reconcile_start()

        self.executor.start.assert_not_called()


if __name__ == "__main__":
    unittest.main()
