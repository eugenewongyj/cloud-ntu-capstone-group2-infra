import unittest
from unittest.mock import Mock

import requests

from telemetry import PrometheusTelemetry


RUN_ID = "a" * 32


class TelemetryTests(unittest.TestCase):

    def setUp(self):
        self.adapter = PrometheusTelemetry(Mock())

    def test_healthy_metrics(self):
        self.adapter.query = Mock(
            side_effect=[
                120, 0, 0, 15,
                995, 995, 995, 995,
            ]
        )

        result = self.adapter.recovery_observation(
            RUN_ID, now=1000
        )

        self.assertEqual(result.p95_ms, 120)
        self.assertEqual(result.request_count, 15)
        self.assertTrue(result.fresh)

    def test_stale_metrics(self):
        self.adapter.query = Mock(
            side_effect=[
                120, 0, 0, 15,
                970, 995, 995, 995,
            ]
        )

        result = self.adapter.recovery_observation(
            RUN_ID, now=1000
        )

        self.assertFalse(result.fresh)

    def test_missing_metrics(self):
        self.adapter.query = Mock(return_value=None)

        result = self.adapter.recovery_observation(
            RUN_ID, now=1000
        )

        self.assertFalse(result.fresh)
        self.assertEqual(result.request_count, 0)

    def test_invalid_run_id(self):
        with self.assertRaises(ValueError):
            self.adapter.recovery_observation("invalid")

    def test_prometheus_unavailable(self):
        self.adapter.session.get.side_effect = (
            requests.ConnectionError("Unavailable")
        )

        result = self.adapter.recovery_observation(
            RUN_ID, now=1000
        )

        self.assertFalse(result.fresh)

    def test_run_isolation(self):
        self.adapter.query = Mock(return_value=1000)

        self.adapter.recovery_observation(
            RUN_ID, now=1000
        )

        for call in self.adapter.query.call_args_list:
            expression = call.args[0]

            self.assertIn(
                f'assessment_run="{RUN_ID}"',
                expression,
            )

            self.assertIn(
                'namespace="retail-store"',
                expression,
            )

            self.assertIn(
                'assessment_phase="recovery"',
                expression,
            )


if __name__ == "__main__":
    unittest.main()
