import logging
import threading
import time

from copy import deepcopy


LOGGER = logging.getLogger("capstone.assessment")

RECONCILE_INTERVAL_SECONDS = 5


class AssessmentEngine:

    def __init__(
        self,
        lifecycle,
        store,
        interval=RECONCILE_INTERVAL_SECONDS,
    ):

        if lifecycle.execution_gate is None:
            raise ValueError(
                "Production execution gate is mandatory"
            )

        if not 1 <= interval <= 10:
            raise ValueError(
                "Invalid reconciliation interval"
            )

        self.lifecycle = lifecycle
        self.store = store
        self.interval = interval

        self.lock = threading.RLock()
        self.shutdown_event = threading.Event()

        self.worker = None
        self.last_success = None
        self.last_error = None

    def start_assessment(
        self,
        profile,
        base_users=1,
        recovery_minutes=10,
        repeat=False,
        max_cycles=3,
    ):

        with self.lock:

            return deepcopy(
                self.lifecycle.start(
                    profile,
                    base_users,
                    recovery_minutes,
                    repeat,
                    max_cycles,
                )
            )

    def stop_assessment(self, run_id):

        with self.lock:

            return deepcopy(
                self.lifecycle.request_stop(run_id)
            )

    def status(self):

        with self.lock:

            state, _ = self.store.read()

            return deepcopy(state)

    def history(self):

        return self.status().get("history", [])

    def reconcile_once(self):

        with self.lock:

            state, _ = self.store.read()

            current = state["state"]

            if current == "starting":

                return self.lifecycle.reconcile_start()

            if current in ("running", "recovering"):

                return self.lifecycle.reconcile_running()

            if current == "stopping":

                return self.lifecycle.reconcile_stop()

            if current in (
                "evaluating",
                "stopped",
                "finalizing",
            ):

                return self.lifecycle.reconcile_finalization()

            if current in ("idle", "blocked"):

                return state

            raise ValueError(
                f"Unknown assessment state: {current}"
            )

    def run(self):

        LOGGER.info(
            "Capstone assessment reconciler started"
        )

        while not self.shutdown_event.is_set():

            try:

                self.reconcile_once()

                self.last_success = time.time()
                self.last_error = None

            except Exception as exc:

                self.last_error = type(exc).__name__

                LOGGER.exception(
                    "Assessment reconciliation failed"
                )

            self.shutdown_event.wait(self.interval)

        LOGGER.info(
            "Capstone assessment reconciler stopped"
        )

    def start_worker(self):

        with self.lock:

            if self.worker and self.worker.is_alive():
                return

            self.shutdown_event.clear()

            self.worker = threading.Thread(
                target=self.run,
                name="capstone-assessment-reconciler",
                daemon=True,
            )

            self.worker.start()

    def shutdown(self, timeout=30):

        self.shutdown_event.set()

        if self.worker:

            self.worker.join(timeout=timeout)

            return not self.worker.is_alive()

        return True

    def health(self):

        worker_running = bool(
            self.worker and self.worker.is_alive()
        )

        age = (
            time.time() - self.last_success
            if self.last_success is not None
            else None
        )

        return {
            "healthy": (
                worker_running
                and self.last_error is None
                and age is not None
                and age <= 120
            ),
            "worker_running": worker_running,
            "last_success": self.last_success,
            "last_error": self.last_error,
            "last_success_age_seconds": age,
        }
