import time

from recovery import RecoveryEvaluator


class RecoveryCoordinator:

    def __init__(self, store, telemetry):
        self.store = store
        self.telemetry = telemetry

    def observe(self, now=None):

        now = time.time() if now is None else now

        state, version = self.store.read()

        if state["state"] != "recovering":
            return state

        if state["stop_requested"]:
            return state

        started = state["recovery_started_at"]

        if started is None:
            raise ValueError("Recovery start time is missing")

        previous = state.get("last_observed_at")

        if previous is not None and now <= previous:
            return state

        evaluator = RecoveryEvaluator(started)

        evaluator.healthy_since = state.get("healthy_since")
        evaluator.last_observed_at = previous
        evaluator.recovered_at = state.get("recovered_at")

        observation = self.telemetry.recovery_observation(
            state["assessment_run"],
            now=now,
        )

        result = evaluator.evaluate(observation)

        elapsed = now - started

        deadline = state["recovery_minutes"] * 60

        current_health_confirmed = (
            result["healthy"]
            and evaluator.healthy_since is not None
            and now - evaluator.healthy_since >= 60
        )

        state.update({
            "healthy_since": evaluator.healthy_since,
            "last_observed_at": evaluator.last_observed_at,
            "recovered_at": evaluator.recovered_at,
            "recovery_seconds": result["recovery_seconds"],
            "recovery_target_met": result["target_met"],
            "current_health_confirmed": current_health_confirmed,
            "telemetry_valid": result["telemetry_valid"],
            "recovery_elapsed_seconds": elapsed,
            "recovery_status": result["state"],
            "latest_metrics": {
                "p95_ms": observation.p95_ms,
                "failure_rate": observation.failure_rate,
                "content_failure_rate":
                    observation.content_failure_rate,
                "request_count": observation.request_count,
                "fresh": observation.fresh,
            },
        })

        if elapsed >= deadline:

            state["state"] = "evaluating"

            if (
                current_health_confirmed
                and evaluator.recovered_at is not None
                and now - started <= deadline + 15
            ):
                state["recovery_outcome"] = "recovered"

            else:
                state["recovery_outcome"] = "unconfirmed"
                state["repeat"] = False

        self.store.write(state, version)

        return state
