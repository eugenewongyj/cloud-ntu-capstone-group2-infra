import re
import time
from copy import deepcopy

from state import initial_state, StateConflict
from recurrence import eligible_for_repeat, next_assessment
from kubernetes.client.exceptions import ApiException


HISTORY_LIMIT = 20

EVIDENCE_FIELDS = (
    "assessment_run",
    "profile",
    "base_users",
    "recovery_minutes",
    "cycle",
    "max_cycles",
    "reserved_at",
    "started_at",
    "execution_started_at",
    "recovery_started_at",
    "observation_deadline",
    "recovered_at",
    "recovery_seconds",
    "recovery_target_met",
    "recovery_outcome",
    "current_health_confirmed",
    "telemetry_valid",
    "last_observed_at",
    "latest_metrics",
    "preflight",
    "job_outcome",
    "stop_requested",
    "stop_requested_at",
    "stopped_at",
    "last_error",
)


def archive_assessment(state, now):

    run_id = state.get("assessment_run")

    if not isinstance(run_id, str) or not re.fullmatch(
        r"[a-f0-9]{32}", run_id
    ):
        raise StateConflict("Invalid assessment identity")

    history = deepcopy(state.get("history", []))

    if any(
        item["assessment_run"] == run_id
        for item in history
    ):
        return history

    record = {
        key: deepcopy(state.get(key))
        for key in EVIDENCE_FIELDS
    }

    record.update({
        "archived_at": now,
        "terminal_state": state["state"],
        "evidence_source": (
            "kubernetes-job-and-prometheus"
        ),
    })

    history.append(record)

    return history[-HISTORY_LIMIT:]


class AssessmentFinalizer:

    def __init__(self, store, executor):
        self.store = store
        self.executor = executor

    def reconcile(self, now=None):

        now = time.time() if now is None else now

        state, version = self.store.read()

        if state["state"] not in (
            "evaluating",
            "stopped",
            "finalizing",
        ):
            return state

        run_id = state.get("assessment_run")

        if not isinstance(run_id, str) or not re.fullmatch(
            r"[a-f0-9]{32}", run_id
        ):
            raise StateConflict("Invalid assessment identity")

        job = self.executor.status()
        job_state = job["state"]

        if (
            job_state != "idle"
            and job.get("assessment_run") != run_id
        ):
            state.update({
                "state": "blocked",
                "repeat": False,
                "last_error":
                    "Unexpected Job identity during finalization",
            })

            self.store.write(state, version)
            return state

        if job_state in (
            "starting",
            "running",
            "stopping",
        ):
            return state

        if job_state not in (
            "idle",
            "completed",
            "failed",
        ):
            return state

        if state["state"] != "finalizing":

            if state["state"] == "stopped":
                state["job_outcome"] = "stopped"
                state["recovery_outcome"] = "unconfirmed"

            elif job_state == "completed":
                state["job_outcome"] = "completed"

                if not (
                    state.get("recovery_outcome") == "recovered"
                    and state.get("current_health_confirmed") is True
                    and state.get("telemetry_valid") is True
                ):
                    state["recovery_outcome"] = "unconfirmed"

            elif (
                job_state == "idle"
                and state.get("job_outcome") == "not_started"
            ):
                state["recovery_outcome"] = "unconfirmed"

            else:
                state["job_outcome"] = (
                    "missing"
                    if job_state == "idle"
                    else "failed"
                )

                state["recovery_outcome"] = "unconfirmed"

            # Preserve recurrence only after successful
            # workload completion and verified recovery.
            state["repeat"] = eligible_for_repeat(state)

            state["history"] = archive_assessment(
                state, now
            )

            state["state"] = "finalizing"

            # Persist evidence before any Job deletion.
            self.store.write(state, version)

            return state

        if not any(
            item["assessment_run"] == run_id
            for item in state.get("history", [])
        ):
            raise StateConflict(
                "Cannot finalize without archived evidence"
            )

        if job_state in ("completed", "failed"):

            try:
                self.executor.stop(run_id)

            except ApiException as exc:
                if exc.status != 404:
                    raise

            return state

        # Job absence has now been confirmed.
        # Reserve a fresh assessment only when eligible.
        if eligible_for_repeat(state):
            updated = next_assessment(state, now)
            self.store.write(updated, version)
            return updated

        # Otherwise reset while retaining history.
        updated = initial_state()

        updated["history"] = deepcopy(
            state.get("history", [])
        )

        updated["last_completed_run"] = run_id

        self.store.write(updated, version)

        return updated
