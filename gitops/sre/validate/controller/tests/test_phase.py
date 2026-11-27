import unittest
from unittest.mock import Mock

from phase import PhaseDetector
from telemetry import TelemetryError


RUN_ID = "a" * 32


class PhaseTests(unittest.TestCase):

    def setUp(self):
        self.telemetry = Mock()
        self.detector = PhaseDetector(self.telemetry)

    def metrics(self, started, sampled, latest=None):
        self.telemetry.query.side_effect = [
            started,
            started if latest is None else latest,
            sampled,
        ]

    def test_load_phase(self):
        self.metrics(1000, 1095)
        result = self.detector.detect(RUN_ID, 5, 1100)
        self.assertEqual(result["phase"], "load")

    def test_recovery_boundary(self):
        self.metrics(1000, 1295)
        result = self.detector.detect(RUN_ID, 5, 1300)
        self.assertEqual(result["phase"], "recovery")
        self.assertEqual(result["recovery_started_at"], 1300)

    def test_five_minute_deadline(self):
        self.metrics(1000, 1595)
        result = self.detector.detect(RUN_ID, 5, 1600)
        self.assertEqual(result["phase"], "observation_ended")

    def test_ten_minute_deadline(self):
        self.metrics(1000, 1895)
        result = self.detector.detect(RUN_ID, 10, 1900)
        self.assertEqual(result["phase"], "observation_ended")

    def test_missing_metrics(self):
        self.metrics(None, None)
        result = self.detector.detect(RUN_ID, 5, 1300)
        self.assertEqual(result["phase"], "unknown")

    def test_stale_metrics(self):
        self.metrics(1000, 1200)
        result = self.detector.detect(RUN_ID, 5, 1300)
        self.assertEqual(result["phase"], "unknown")

    def test_inconsistent_execution_clock(self):
        self.metrics(1000, 1295, latest=1100)
        result = self.detector.detect(RUN_ID, 5, 1300)
        self.assertEqual(result["phase"], "unknown")

    def test_prometheus_unavailable(self):
        self.telemetry.query.side_effect = TelemetryError()
        result = self.detector.detect(RUN_ID, 5, 1300)
        self.assertEqual(result["phase"], "unknown")

    def test_invalid_run_id(self):
        with self.assertRaises(ValueError):
            self.detector.detect("invalid", 5)

    def test_invalid_recovery_duration(self):
        with self.assertRaises(ValueError):
            self.detector.detect(RUN_ID, 20)


if __name__ == "__main__":
    unittest.main()
