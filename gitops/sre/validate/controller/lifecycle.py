import uuid
import time

from state import initial_state, StateConflict
from execution import AssessmentConflict
from phase import PhaseDetector
from recovery_coordinator import RecoveryCoordinator
from finalization import AssessmentFinalizer


class AssessmentLifecycle:

    def __init__(self, store, executor, telemetry,
                 execution_gate=None):
        self.store = store
        self.executor = executor
        self.telemetry = telemetry
        self.execution_gate = execution_gate
        self.phase_detector = PhaseDetector(telemetry)
        self.recovery = RecoveryCoordinator(store, telemetry)
        self.finalizer = AssessmentFinalizer(store, executor)

    def start(self, profile, base_users=1,
              recovery_minutes=10, repeat=False,
              max_cycles=3):

        if profile not in ("normal", "1111"):
            raise ValueError("Invalid assessment profile")

        if type(base_users) is not int or not 1 <= base_users <= 10:
            raise ValueError("BASE_USERS must be 1-10")

        if type(recovery_minutes) is not int or not 5 <= recovery_minutes <= 10:
            raise ValueError("Recovery must be 5-10 minutes")

        if type(repeat) is not bool:
            raise ValueError("Invalid repeat setting")

        if type(max_cycles) is not int or not 1 <= max_cycles <= 3:
            raise ValueError("Maximum cycles must be 1-3")

        current, version = self.store.read()

        if current["state"] != "idle":
            raise StateConflict("Assessment is not idle")

        if self.executor.status()["state"] != "idle":
            raise AssessmentConflict("Existing Job detected")

        state = initial_state()
        state["history"] = current.get("history", [])
        state["last_completed_run"] = current.get("last_completed_run")

        state.update({
            "state": "starting",
            "assessment_run": uuid.uuid4().hex,
            "profile": profile,
            "base_users": base_users,
            "recovery_minutes": recovery_minutes,
            "repeat": repeat,
            "cycle": 1,
            "max_cycles": max_cycles if repeat else 1,
            "reserved_at": time.time(),
        })

        self.store.write(state, version)

        return state

    def reconcile_start(self):

        state, version = self.store.read()

        if state["state"] != "starting":
            return state

        if state["stop_requested"]:
            return state

        if time.time() < state.get("not_before", 0):
            return state

        run_id = state["assessment_run"]

        job = self.executor.status()

        if job["state"] == "idle":

            if (
                state.get("repeat") is True
                and self.execution_gate is None
            ):
                raise StateConflict(
                    "Recurring assessments require execution gate"
                )

            if self.execution_gate is not None:

                gate_result = self.execution_gate.evaluate()

                state["preflight"] = gate_result

                if gate_result.get("healthy") is not True:

                    state.update({
                        "state": "evaluating",
                        "repeat": False,
                        "job_outcome": "not_started",
                        "recovery_outcome": "unconfirmed",
                        "last_error":
                            "Production preflight failed",
                    })

                    self.store.write(state, version)

                    return state

                version = self.store.write(
                    state, version
                )

            try:
                self.executor.start(
                    state["profile"],
                    state["base_users"],
                    state["recovery_minutes"],
                    run_id=run_id,
                )

            except AssessmentConflict:
                pass

            job = self.executor.status()

        if job["state"] == "idle":
            return state

        if job.get("assessment_run") != run_id:
            state["state"] = "blocked"
            state["last_error"] = "Unexpected Job identity"

        elif job["state"] == "running":
            state["state"] = "running"
            state["started_at"] = job.get("started_at")

        elif job["state"] in ("completed", "failed"):
            state["state"] = "evaluating"
            state["job_outcome"] = job["state"]

        elif job["state"] == "stopping":
            state["state"] = "blocked"
            state["last_error"] = "Job is being deleted"

        else:
            return state

        self.store.write(state, version)

        return state


    def reconcile_running(self, now=None):

        now = time.time() if now is None else now

        state, version = self.store.read()

        if state["state"] not in ("running", "recovering"):
            return state

        if state["stop_requested"]:
            return state

        job = self.executor.status()

        if job["state"] == "idle":
            state.update({
                "state": "evaluating",
                "job_outcome": "missing",
                "recovery_outcome": "unconfirmed",
                "repeat": False,
                "last_error": "Assessment Job disappeared",
            })

            self.store.write(state, version)
            return state

        if job.get("assessment_run") != state["assessment_run"]:
            state.update({
                "state": "blocked",
                "repeat": False,
                "last_error": "Unexpected Job identity",
            })

            self.store.write(state, version)
            return state

        if job["state"] in ("failed", "stopping"):
            state.update({
                "state": "evaluating",
                "job_outcome": job["state"],
                "recovery_outcome": "unconfirmed",
                "repeat": False,
            })

            self.store.write(state, version)
            return state

        if state.get("execution_started_at") is None:

            detected = self.phase_detector.detect(
                state["assessment_run"],
                state["recovery_minutes"],
                now=now,
            )

            if detected["phase"] != "unknown":
                state.update({
                    "execution_started_at":
                        detected["execution_started_at"],
                    "recovery_started_at":
                        detected["recovery_started_at"],
                    "observation_deadline":
                        detected["observation_deadline"],
                })

                version = self.store.write(state, version)

        recovery_start = state.get("recovery_started_at")
        deadline = state.get("observation_deadline")

        if recovery_start is None:

            if job["state"] == "completed":
                state.update({
                    "state": "evaluating",
                    "job_outcome": "completed",
                    "recovery_outcome": "unconfirmed",
                    "repeat": False,
                    "last_error": "Execution clock unavailable",
                })

                self.store.write(state, version)

            return state

        if job["state"] == "completed":

            state["job_outcome"] = "completed"

            if now < deadline:
                state.update({
                    "state": "evaluating",
                    "recovery_outcome": "unconfirmed",
                    "repeat": False,
                    "last_error": "Job ended before deadline",
                })

                self.store.write(state, version)
                return state

            version = self.store.write(state, version)

        if now < recovery_start:
            return state

        if state["state"] == "running":
            state["state"] = "recovering"
            self.store.write(state, version)

        return self.recovery.observe(now=now)


    def request_stop(self, run_id):

        state, version = self.store.read()

        if state.get("assessment_run") != run_id or not run_id:
            raise StateConflict("Assessment identity mismatch")

        if state["state"] == "stopped":
            return state

        if state["state"] == "stopping":
            return state

        if state["state"] == "finalizing":

            state.update({
                "repeat": False,
                "stop_requested": True,
                "stop_requested_at": time.time(),
            })

            self.store.write(state, version)
            return state

        if state["state"] not in (
            "starting",
            "running",
            "recovering",
            "evaluating",
        ):
            raise StateConflict("Assessment cannot be stopped")

        state.update({
            "state": "stopping",
            "stop_requested": True,
            "repeat": False,
            "stop_requested_at": time.time(),
            "recovery_outcome": "unconfirmed",
        })

        self.store.write(state, version)

        return state

    def reconcile_stop(self, now=None):

        now = time.time() if now is None else now

        state, version = self.store.read()

        if state["state"] != "stopping":
            return state

        if not state["stop_requested"]:
            raise StateConflict("Missing stop authorization")

        job = self.executor.status()

        if job["state"] == "idle":

            state.update({
                "state": "stopped",
                "stopped_at": now,
                "repeat": False,
                "job_outcome": "stopped",
                "recovery_outcome": "unconfirmed",
            })

            self.store.write(state, version)

            return state

        if job.get("assessment_run") != state["assessment_run"]:

            state.update({
                "state": "blocked",
                "repeat": False,
                "last_error": "Unexpected Job identity during stop",
            })

            self.store.write(state, version)

            return state

        if job["state"] == "stopping":
            return state

        self.executor.stop(state["assessment_run"])

        return state


    def reconcile_finalization(self, now=None):

        return self.finalizer.reconcile(now=now)
