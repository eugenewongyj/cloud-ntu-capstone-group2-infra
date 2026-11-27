import unittest

from recurrence import (
    eligible_for_repeat,
    next_assessment,
    COOLDOWN_SECONDS,
)

from state import initial_state


class RecurrenceTests(unittest.TestCase):

    def setUp(self):

        self.state = initial_state()

        self.state.update({
            "state": "finalizing",
            "assessment_run": "a" * 32,
            "profile": "1111",
            "base_users": 1,
            "recovery_minutes": 10,
            "repeat": True,
            "cycle": 1,
            "max_cycles": 3,
            "job_outcome": "completed",
            "recovery_outcome": "recovered",
            "current_health_confirmed": True,
            "telemetry_valid": True,
            "recovery_target_met": True,
        })

    def test_successful_assessment_eligible(self):
        self.assertTrue(
            eligible_for_repeat(self.state)
        )

    def test_repeat_disabled(self):
        self.state["repeat"] = False
        self.assertFalse(
            eligible_for_repeat(self.state)
        )

    def test_stop_requested(self):
        self.state["stop_requested"] = True
        self.assertFalse(
            eligible_for_repeat(self.state)
        )

    def test_failed_job(self):
        self.state["job_outcome"] = "failed"
        self.assertFalse(
            eligible_for_repeat(self.state)
        )

    def test_unconfirmed_recovery(self):
        self.state["recovery_outcome"] = "unconfirmed"
        self.assertFalse(
            eligible_for_repeat(self.state)
        )

    def test_invalid_telemetry(self):
        self.state["telemetry_valid"] = False
        self.assertFalse(
            eligible_for_repeat(self.state)
        )

    def test_health_not_confirmed(self):
        self.state["current_health_confirmed"] = False
        self.assertFalse(
            eligible_for_repeat(self.state)
        )

    def test_recovery_target_missed(self):
        self.state["recovery_target_met"] = False
        self.assertFalse(
            eligible_for_repeat(self.state)
        )

    def test_cycle_limit_reached(self):
        self.state["cycle"] = 3
        self.assertFalse(
            eligible_for_repeat(self.state)
        )

    def test_excessive_cycle_limit(self):
        self.state["max_cycles"] = 4
        self.assertFalse(
            eligible_for_repeat(self.state)
        )

    def test_new_assessment_identity(self):
        updated = next_assessment(
            self.state, now=1000
        )
        self.assertNotEqual(
            updated["assessment_run"],
            self.state["assessment_run"],
        )
        self.assertEqual(
            len(updated["assessment_run"]), 32
        )

    def test_original_parameters_preserved(self):
        updated = next_assessment(self.state)

        for key in (
            "profile",
            "base_users",
            "recovery_minutes",
            "max_cycles",
        ):
            self.assertEqual(
                updated[key], self.state[key]
            )

    def test_cycle_incremented(self):
        updated = next_assessment(self.state)
        self.assertEqual(updated["cycle"], 2)

    def test_cooldown_enforced(self):
        updated = next_assessment(
            self.state, now=1000
        )
        self.assertEqual(
            updated["not_before"],
            1000 + COOLDOWN_SECONDS,
        )

    def test_recovery_state_reset(self):
        updated = next_assessment(self.state)
        self.assertIsNone(updated["recovered_at"])
        self.assertIsNone(updated["recovery_seconds"])
        self.assertEqual(updated["state"], "starting")

    def test_history_preserved(self):
        self.state["history"] = [
            {"assessment_run": "a" * 32}
        ]

        updated = next_assessment(self.state)

        self.assertEqual(
            updated["history"],
            self.state["history"],
        )

        self.assertIsNot(
            updated["history"],
            self.state["history"],
        )

    def test_ineligible_transition_rejected(self):
        self.state["repeat"] = False

        with self.assertRaises(ValueError):
            next_assessment(self.state)


if __name__ == "__main__":
    unittest.main()
