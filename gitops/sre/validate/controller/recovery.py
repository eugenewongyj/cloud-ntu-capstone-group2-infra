import math
from dataclasses import dataclass
from typing import Optional


@dataclass(frozen=True)
class RecoveryObservation:
    timestamp: float
    p95_ms: Optional[float]
    failure_rate: Optional[float]
    content_failure_rate: Optional[float]
    request_count: int
    fresh: bool


class RecoveryEvaluator:

    def __init__(self, recovery_started_at):
        self.started_at = recovery_started_at
        self.healthy_since = None
        self.last_observed_at = None
        self.recovered_at = None

    def evaluate(self, observation):

        now = observation.timestamp

        if now < self.started_at:
            raise ValueError("Observation precedes recovery")

        if (
            self.last_observed_at is not None
            and now <= self.last_observed_at
        ):
            raise ValueError("Observation must advance")

        elapsed = now - self.started_at

        if (
            self.last_observed_at is not None
            and now - self.last_observed_at > 15
        ):
            self.healthy_since = None

        self.last_observed_at = now

        values = (
            observation.p95_ms,
            observation.failure_rate,
            observation.content_failure_rate,
        )

        valid = (
            observation.fresh
            and observation.request_count > 0
            and all(
                value is not None
                and math.isfinite(value)
                and value >= 0
                for value in values
            )
        )

        healthy = (
            valid
            and observation.p95_ms < 500
            and observation.failure_rate < 0.01
            and observation.content_failure_rate < 0.01
        )

        if healthy:
            if self.healthy_since is None:
                self.healthy_since = now
        else:
            self.healthy_since = None

        sustained = (
            self.healthy_since is not None
            and now - self.healthy_since >= 60
        )

        if sustained and elapsed <= 600:
            if self.recovered_at is None:
                self.recovered_at = self.healthy_since

        if self.recovered_at is not None:
            state = "recovered"
        elif elapsed >= 600:
            state = "timeout"
        elif not valid:
            state = "insufficient_telemetry"
        else:
            state = "recovering"

        recovery_seconds = (
            self.recovered_at - self.started_at
            if self.recovered_at is not None
            else None
        )

        return {
            "state": state,
            "elapsed_seconds": elapsed,
            "healthy": healthy,
            "telemetry_valid": valid,
            "recovery_seconds": recovery_seconds,
            "target_met": (
                recovery_seconds <= 300
                if recovery_seconds is not None
                else None
            ),
        }
