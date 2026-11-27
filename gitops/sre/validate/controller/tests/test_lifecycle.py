import unittest
from unittest.mock import Mock

from lifecycle import AssessmentLifecycle
from state import initial_state, StateConflict
from execution import AssessmentConflict


class LifecycleTests(unittest.TestCase):

    def setUp(self):
        self.store = Mock()
        self.executor = Mock()
        self.telemetry = Mock()

        self.store.read.return_value = (
            initial_state(), "100"
        )

        self.executor.status.return_value = {
            "state": "idle"
        }

        self.lifecycle = AssessmentLifecycle(
            self.store,
            self.executor,
            self.telemetry,
        )

    def reserved_state(self):
        state = initial_state()

        state.update({
            "state": "starting",
            "assessment_run": "a" * 32,
            "profile": "1111",
        })

        self.store.read.return_value = (
            state, "101"
        )

        return state

    def test_reserve_normal_sale(self):
        result = self.lifecycle.start("normal")

        self.assertEqual(result["state"], "starting")
        self.assertEqual(result["profile"], "normal")
        self.assertEqual(len(result["assessment_run"]), 32)

        self.store.write.assert_called_once()
        self.executor.start.assert_not_called()

    def test_reserve_flash_sale(self):
        result = self.lifecycle.start(
            "1111", 1, 10, True, 3
        )

        self.assertEqual(result["profile"], "1111")
        self.assertTrue(result["repeat"])
        self.assertEqual(result["max_cycles"], 3)

    def test_duplicate_start_rejected(self):
        self.reserved_state()

        with self.assertRaises(StateConflict):
            self.lifecycle.start("normal")

        self.store.write.assert_not_called()

    def test_existing_job_rejected(self):
        self.executor.status.return_value = {
            "state": "running"
        }

        with self.assertRaises(AssessmentConflict):
            self.lifecycle.start("normal")

        self.store.write.assert_not_called()

    def test_excessive_cycles_rejected(self):
        with self.assertRaises(ValueError):
            self.lifecycle.start(
                "1111", repeat=True, max_cycles=4
            )

        self.store.write.assert_not_called()

    def test_reconcile_creates_reserved_job(self):
        self.reserved_state()

        self.executor.status.side_effect = [
            {"state": "idle"},
            {
                "state": "running",
                "assessment_run": "a" * 32,
                "started_at": "2026-11-27T15:00:00Z",
            },
        ]

        result = self.lifecycle.reconcile_start()

        self.executor.start.assert_called_once_with(
            "1111", 1, 10, run_id="a" * 32
        )

        self.assertEqual(result["state"], "running")

    def test_reconcile_existing_matching_job(self):
        self.reserved_state()

        self.executor.status.return_value = {
            "state": "running",
            "assessment_run": "a" * 32,
        }

        result = self.lifecycle.reconcile_start()

        self.assertEqual(result["state"], "running")
        self.executor.start.assert_not_called()

    def test_unexpected_job_identity(self):
        self.reserved_state()

        self.executor.status.return_value = {
            "state": "running",
            "assessment_run": "b" * 32,
        }

        result = self.lifecycle.reconcile_start()

        self.assertEqual(result["state"], "blocked")
        self.executor.start.assert_not_called()

    def test_stop_requested_prevents_creation(self):
        state = self.reserved_state()
        state["stop_requested"] = True

        self.lifecycle.reconcile_start()

        self.executor.start.assert_not_called()

    def test_concurrent_reservation_rejected(self):
        self.store.write.side_effect = StateConflict()

        with self.assertRaises(StateConflict):
            self.lifecycle.start("normal")

        self.executor.start.assert_not_called()


if __name__ == "__main__":
    unittest.main()
