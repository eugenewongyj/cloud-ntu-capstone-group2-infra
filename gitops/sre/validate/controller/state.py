import json
from copy import deepcopy

from kubernetes import client
from kubernetes.client.exceptions import ApiException

NAMESPACE = "monitoring"
STATE_NAME = "capstone-assessment-state"


class StateConflict(Exception):
    pass


def initial_state():
    return {
        "state": "idle",
        "assessment_run": None,
        "profile": None,
        "base_users": 1,
        "recovery_minutes": 10,
        "repeat": False,
        "cycle": 0,
        "max_cycles": 3,
        "stop_requested": False,
        "started_at": None,
        "recovery_started_at": None,
        "recovery_seconds": None,
        "healthy_since": None,
        "last_observed_at": None,
        "recovered_at": None,
        "job_uid": None,
        "last_error": None,
        "history": [],
        "last_completed_run": None,
    }


class AssessmentStateStore:

    def __init__(self, core_api):
        self.core = core_api

    def read(self):
        resource = self.core.read_namespaced_config_map(
            STATE_NAME,
            NAMESPACE,
        )

        state = json.loads(resource.data["state.json"])

        return state, resource.metadata.resource_version

    def write(self, state, resource_version):

        if not resource_version:
            raise ValueError("resourceVersion is required")

        body = client.V1ConfigMap(
            metadata=client.V1ObjectMeta(
                name=STATE_NAME,
                namespace=NAMESPACE,
                resource_version=resource_version,
            ),
            data={
                "state.json": json.dumps(
                    state,
                    sort_keys=True,
                    allow_nan=False,
                )
            },
        )

        try:
            result = self.core.patch_namespaced_config_map(
                name=STATE_NAME,
                namespace=NAMESPACE,
                body=body,
            )

        except ApiException as exc:
            if exc.status == 409:
                raise StateConflict(
                    "Assessment state changed concurrently"
                ) from exc
            raise

        return result.metadata.resource_version

    def transition(self, expected_states, updates):

        state, version = self.read()

        if state["state"] not in expected_states:
            raise StateConflict(
                "Invalid assessment state transition"
            )

        updated = deepcopy(state)
        updated.update(updates)

        new_version = self.write(updated, version)

        return updated, new_version
