import unittest
from copy import deepcopy
from unittest.mock import Mock

from finalization import (
    AssessmentFinalizer,
    archive_assessment,
    HISTORY_LIMIT,
)
from lifecycle import AssessmentLifecycle
from state import initial_state, StateConflict


RUN_ID = "a" * 32


class FinalizationTests(unittest.TestCase):

    def setUp(self):

        self.store = Mock()
        self.executor = Mock()

        self.state = initial_state()

        self.state.update({
            "state": "evaluating",
            "assessment_run": RUN_ID,
            "profile": "1111",
            "repeat": True,
            "recovery_outcome": "recovered",
            "current_health_confirmed": True,
            "telemetry_valid": True,
            "recovery_seconds": 42,
            "latest_metrics": {
                "p95_ms": 120,
            },
        })

        self.version = 100

        self.store.read.side_effect = (
            lambda: (
                deepcopy(self.state),
                str(self.version),
            )
        )

        self.store.write.side_effect = self.persist

        self.executor.status.return_value = {
            "state": "completed",
            "assessment_run": RUN_ID,
        }

        self.finalizer = AssessmentFinalizer(
            self.store,
            self.executor,
        )

    def persist(self, state, version):

        self.assertEqual(version, str(self.version))

        self.state = deepcopy(state)
        self.version += 1

        return str(self.version)

    def test_archive_before_delete(self):

        result = self.finalizer.reconcile(now=1000)

        self.assertEqual(result["state"], "finalizing")
        self.assertEqual(len(result["history"]), 1)

        self.executor.stop.assert_not_called()

    def test_preserve_measured_recovery(self):

        result = self.finalizer.reconcile(now=1000)

        record = result["history"][0]

        self.assertEqual(record["recovery_seconds"], 42)
        self.assertEqual(record["latest_metrics"]["p95_ms"], 120)

    def test_active_job_is_not_deleted(self):

        self.executor.status.return_value["state"] = "running"

        result = self.finalizer.reconcile(now=1000)

        self.assertEqual(result["state"], "evaluating")

        self.executor.stop.assert_not_called()
        self.store.write.assert_not_called()

    def test_failed_job_is_not_recovered(self):

        self.executor.status.return_value["state"] = "failed"

        result = self.finalizer.reconcile(now=1000)

        record = result["history"][0]

        self.assertEqual(record["job_outcome"], "failed")
        self.assertEqual(record["recovery_outcome"], "unconfirmed")
        self.assertFalse(result["repeat"])

    def test_missing_job_is_not_success(self):

        self.executor.status.return_value = {
            "state": "idle"
        }

        result = self.finalizer.reconcile(now=1000)

        self.assertEqual(
            result["history"][0]["job_outcome"],
            "missing",
        )

    def test_unrelated_job_is_not_deleted(self):

        self.executor.status.return_value[
            "assessment_run"
        ] = "b" * 32

        result = self.finalizer.reconcile(now=1000)

        self.assertEqual(result["state"], "blocked")

        self.executor.stop.assert_not_called()

    def test_cleanup_after_archival(self):

        self.finalizer.reconcile(now=1000)
        self.finalizer.reconcile(now=1001)

        self.executor.stop.assert_called_once_with(RUN_ID)

    def test_wait_for_job_deletion(self):

        self.finalizer.reconcile(now=1000)

        self.executor.status.return_value["state"] = "stopping"

        result = self.finalizer.reconcile(now=1001)

        self.assertEqual(result["state"], "finalizing")

        self.executor.stop.assert_not_called()

    def test_reset_preserves_history(self):

        self.finalizer.reconcile(now=1000)

        self.executor.status.return_value = {
            "state": "idle"
        }

        result = self.finalizer.reconcile(now=1001)

        self.assertEqual(result["state"], "idle")
        self.assertEqual(len(result["history"]), 1)
        self.assertEqual(result["last_completed_run"], RUN_ID)

    def test_archive_is_idempotent(self):

        self.state["history"] = archive_assessment(
            self.state, 1000
        )

        history = archive_assessment(
            self.state, 1001
        )

        self.assertEqual(len(history), 1)
        self.assertEqual(history[0]["archived_at"], 1000)

    def test_history_is_bounded(self):

        self.state["history"] = [
            {"assessment_run": f"{i:032x}"}
            for i in range(HISTORY_LIMIT)
        ]

        history = archive_assessment(
            self.state, 1000
        )

        self.assertEqual(len(history), HISTORY_LIMIT)
        self.assertEqual(history[-1]["assessment_run"], RUN_ID)

    def test_missing_telemetry_prevents_success(self):

        self.state["telemetry_valid"] = False

        result = self.finalizer.reconcile(now=1000)

        self.assertEqual(
            result["history"][0]["recovery_outcome"],
            "unconfirmed",
        )

    def test_stopped_assessment_is_archived(self):

        self.state["state"] = "stopped"

        self.executor.status.return_value = {
            "state": "idle"
        }

        result = self.finalizer.reconcile(now=1000)

        record = result["history"][0]

        self.assertEqual(record["job_outcome"], "stopped")
        self.assertEqual(record["recovery_outcome"], "unconfirmed")

    def test_new_start_preserves_history(self):

        self.state = initial_state()

        self.state["history"] = [
            {"assessment_run": RUN_ID}
        ]

        self.executor.status.return_value = {
            "state": "idle"
        }

        lifecycle = AssessmentLifecycle(
            self.store,
            self.executor,
            Mock(),
        )

        result = lifecycle.start("normal")

        self.assertEqual(len(result["history"]), 1)
        self.assertNotEqual(result["assessment_run"], RUN_ID)

    def test_cleanup_requires_archive(self):

        self.state["state"] = "finalizing"
        self.state["history"] = []

        with self.assertRaises(StateConflict):
            self.finalizer.reconcile(now=1000)

        self.executor.stop.assert_not_called()

    def test_repeat_remains_disabled(self):

        result = self.finalizer.reconcile(now=1000)

        self.assertFalse(result["repeat"])


if __name__ == "__main__":
    unittest.main()
