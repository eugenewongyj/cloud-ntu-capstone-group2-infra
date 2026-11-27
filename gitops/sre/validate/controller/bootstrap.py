import json
import os
import logging

from kubernetes import client, config
from kubernetes.client.exceptions import ApiException

from execution import AssessmentExecutor
from state import AssessmentStateStore
from telemetry import PrometheusTelemetry
from health_gate import InfrastructureHealthGate
from monitoring_integrity import MonitoringIntegrityGate
from execution_gate import ExecutionGate
from lifecycle import AssessmentLifecycle
from engine import AssessmentEngine
from api import create_app


LOGGER = logging.getLogger("capstone.bootstrap")

NAMESPACE = "monitoring"

STATE_CONFIGMAP = "capstone-assessment-state"


def initialize_state(core_api):

    try:

        existing = core_api.read_namespaced_config_map(
            name=STATE_CONFIGMAP,
            namespace=NAMESPACE,
            _request_timeout=10,
        )

    except ApiException as error:
        if error.status == 404:
            raise RuntimeError(
                "Assessment state must be provisioned by GitOps"
            ) from error
        raise

    raw = (existing.data or {}).get("state.json")

    if not raw:
        raise RuntimeError(
            "Persistent assessment state is missing"
        )

    state = json.loads(raw)

    if not isinstance(state, dict):
        raise RuntimeError(
            "Invalid persistent assessment state"
        )

    if "state" not in state:
        raise RuntimeError(
            "Assessment lifecycle state is missing"
        )

    return state


def build_engine():

    # Production must authenticate using the Pod's
    # Kubernetes ServiceAccount.
    # No local kubeconfig fallback is permitted.

    config.load_incluster_config()

    core_api = client.CoreV1Api()

    batch_api = client.BatchV1Api()

    apps_api = client.AppsV1Api()

    autoscaling_api = client.AutoscalingV2Api()

    initialize_state(core_api)

    store = AssessmentStateStore(core_api)

    executor = AssessmentExecutor(
        batch_api,
        core_api,
    )

    telemetry = PrometheusTelemetry()

    infrastructure = InfrastructureHealthGate(
        apps_api,
        autoscaling_api,
        telemetry,
    )

    monitoring = MonitoringIntegrityGate()

    gate = ExecutionGate(
        infrastructure,
        monitoring,
    )

    lifecycle = AssessmentLifecycle(
        store,
        executor,
        telemetry,
        execution_gate=gate,
    )

    return AssessmentEngine(
        lifecycle,
        store,
        interval=5,
    )


def build_application():

    token = os.environ.get(
        "CAPSTONE_CONTROLLER_TOKEN", ""
    )

    if len(token) < 32:

        raise RuntimeError(
            "Controller authentication is not configured"
        )

    engine = build_engine()

    app = create_app(
        engine,
        token,
        max_base_users=int(
            os.environ.get(
                "CAPSTONE_MAX_BASE_USERS", "1"
            )
        ),
    )

    app.extensions[
        "capstone_assessment_engine"
    ] = engine

    return app
