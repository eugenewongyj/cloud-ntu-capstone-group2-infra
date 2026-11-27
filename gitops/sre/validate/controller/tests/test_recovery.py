import unittest

from recovery import (
    RecoveryEvaluator,
    RecoveryObservation,
)


def observation(t, latency=100, failure=0,
                content=0, count=10, fresh=True):
    return RecoveryObservation(
        timestamp=t,
        p95_ms=latency,
        failure_rate=failure,
        content_failure_rate=content,
        request_count=count,
        fresh=fresh,
    )


class RecoveryTests(unittest.TestCase):

    def test_sustained_recovery(self):
        evaluator = RecoveryEvaluator(0)

        for t in range(0, 61, 10):
            result = evaluator.evaluate(observation(t))

        self.assertEqual(result["state"], "recovered")
        self.assertEqual(result["recovery_seconds"], 0)
        self.assertTrue(result["target_met"])

    def test_latency_breach(self):
        evaluator = RecoveryEvaluator(0)

        result = evaluator.evaluate(
            observation(10, latency=600)
        )

        self.assertFalse(result["healthy"])

    def test_failure_breach(self):
        evaluator = RecoveryEvaluator(0)

        result = evaluator.evaluate(
            observation(10, failure=0.02)
        )

        self.assertFalse(result["healthy"])

    def test_content_failure(self):
        evaluator = RecoveryEvaluator(0)

        result = evaluator.evaluate(
            observation(10, content=0.02)
        )

        self.assertFalse(result["healthy"])

    def test_missing_telemetry(self):
        evaluator = RecoveryEvaluator(0)

        result = evaluator.evaluate(
            observation(10, latency=None)
        )

        self.assertEqual(
            result["state"], "insufficient_telemetry"
        )

    def test_stale_telemetry(self):
        evaluator = RecoveryEvaluator(0)

        result = evaluator.evaluate(
            observation(10, fresh=False)
        )

        self.assertFalse(result["telemetry_valid"])

    def test_zero_requests(self):
        evaluator = RecoveryEvaluator(0)

        result = evaluator.evaluate(
            observation(10, count=0)
        )

        self.assertFalse(result["telemetry_valid"])

    def test_observation_gap(self):
        evaluator = RecoveryEvaluator(0)

        evaluator.evaluate(observation(0))

        result = evaluator.evaluate(observation(60))

        self.assertEqual(result["state"], "recovering")

    def test_recovery_timeout(self):
        evaluator = RecoveryEvaluator(0)

        result = evaluator.evaluate(
            observation(600, latency=900)
        )

        self.assertEqual(result["state"], "timeout")

    def test_health_interruption(self):
        evaluator = RecoveryEvaluator(0)

        for t in range(0, 51, 10):
            evaluator.evaluate(observation(t))

        evaluator.evaluate(observation(60, latency=900))

        result = evaluator.evaluate(observation(70))

        self.assertEqual(result["state"], "recovering")


if __name__ == "__main__":
    unittest.main()
