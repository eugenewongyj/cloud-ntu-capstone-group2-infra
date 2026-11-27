import math
import re
import time

from telemetry import TelemetryError


class PhaseDetector:

    def __init__(self, telemetry):
        self.telemetry = telemetry

    def detect(self, run_id, recovery_minutes, now=None):

        if not re.fullmatch(r"[a-f0-9]{32}", run_id):
            raise ValueError("Invalid assessment identifier")

        if type(recovery_minutes) is not int or not 5 <= recovery_minutes <= 10:
            raise ValueError("Invalid recovery duration")

        now = time.time() if now is None else now

        selector = (
            '{project="Capstone",'
            'namespace="retail-store",'
            f'assessment_run="{run_id}"'
            '}'
        )

        metric = (
            "k6_capstone_execution_start_seconds"
            + selector
        )

        try:
            started = self.telemetry.query(
                f"min({metric})", now
            )

            latest_start = self.telemetry.query(
                f"max({metric})", now
            )

            sampled = self.telemetry.query(
                f"min(timestamp({metric}))", now
            )

        except TelemetryError:
            return {"phase": "unknown"}

        if (
            started is None
            or latest_start is None
            or sampled is None
            or not all(
                math.isfinite(v)
                for v in (started, latest_start, sampled)
            )
            or started <= 0
            or started > now
            or abs(latest_start - started) > 1
            or not 0 <= now - sampled <= 15
        ):
            return {"phase": "unknown"}

        elapsed = now - started
        recovery_start = started + 300
        deadline = recovery_start + recovery_minutes * 60

        if now >= deadline:
            phase = "observation_ended"
        elif elapsed >= 300:
            phase = "recovery"
        else:
            phase = "load"

        return {
            "phase": phase,
            "execution_started_at": started,
            "elapsed_seconds": elapsed,
            "recovery_started_at": recovery_start,
            "observation_deadline": deadline,
        }
