import copy
import re
import uuid

import yaml
from kubernetes import client
from kubernetes.client.exceptions import ApiException

NAMESPACE = "monitoring"
JOB_NAME = "capstone-assessment-active"
CONFIGMAP_NAME = "capstone-k6-workload"


class AssessmentConflict(Exception):
    pass


class AssessmentExecutor:

    def __init__(self, batch_api, core_api):
        self.batch = batch_api
        self.core = core_api

    def start(self, profile, base_users=1,
              recovery_minutes=10, run_id=None):
        if profile not in ("normal", "1111"):
            raise ValueError("Invalid assessment profile")

        if type(base_users) is not int or not 1 <= base_users <= 10:
            raise ValueError("BASE_USERS must be 1-10")

        if type(recovery_minutes) is not int or not 5 <= recovery_minutes <= 10:
            raise ValueError("Recovery must be 5-10 minutes")

        if run_id is None:
            run_id = uuid.uuid4().hex

        if not isinstance(run_id, str) or not re.fullmatch(
            r"[a-f0-9]{32}", run_id
        ):
            raise ValueError("Invalid assessment identifier")

        configmap = self.core.read_namespaced_config_map(
            CONFIGMAP_NAME, NAMESPACE
        )

        job = copy.deepcopy(
            yaml.safe_load(configmap.data["job-template.yaml"])
        )

        container = job["spec"]["template"]["spec"]["containers"][0]

        configured_env = {
            item["name"]: item.get("value")
            for item in container["env"]
        }

        required_env = {
            "TARGET_HOST":
                "https://group2-shop.sctp-sandbox.com",
            "CAPSTONE_PRODUCT_PATH":
                "/catalog",
            "CAPSTONE_EXPECT_TEXT":
                "These products are for demonstration purposes only",
            "K6_PROMETHEUS_RW_SERVER_URL":
                "http://kube-prometheus-stack-prometheus."
                "monitoring.svc.cluster.local:9090/api/v1/write",
        }

        for key, expected in required_env.items():
            if configured_env.get(key) != expected:
                raise ValueError(
                    f"Unauthorized workload configuration: {key}"
                )

        if job["metadata"]["namespace"] != NAMESPACE:
            raise ValueError("Unauthorized execution namespace")

        job["metadata"]["name"] = JOB_NAME
        job["metadata"]["namespace"] = NAMESPACE
        job["metadata"]["labels"]["assessment-run"] = run_id

        job["spec"]["suspend"] = False

        pod = job["spec"]["template"]
        pod["metadata"]["labels"]["assessment-run"] = run_id

        values = {
            "LOAD_PROFILE": profile,
            "BASE_USERS": str(base_users),
            "RECOVERY_MINUTES": str(recovery_minutes),
            "ASSESSMENT_RUN": run_id,
        }

        for env in pod["spec"]["containers"][0]["env"]:
            if env["name"] in values:
                env["value"] = values[env["name"]]

        try:
            self.batch.create_namespaced_job(
                namespace=NAMESPACE,
                body=job,
            )
        except ApiException as exc:
            if exc.status == 409:
                raise AssessmentConflict(
                    "An assessment already exists"
                ) from exc
            raise

        return {
            "assessment_run": run_id,
            "profile": profile,
            "base_users": base_users,
            "recovery_minutes": recovery_minutes,
            "state": "starting",
        }

    def status(self):
        try:
            job = self.batch.read_namespaced_job(
                JOB_NAME, NAMESPACE
            )
        except ApiException as exc:
            if exc.status == 404:
                return {"state": "idle"}
            raise

        status = job.status
        state = "starting"

        if job.metadata.deletion_timestamp:
            state = "stopping"
        else:
            for condition in status.conditions or []:
                if condition.status == "True":
                    if condition.type == "Complete":
                        state = "completed"
                    elif condition.type == "Failed":
                        state = "failed"

            if state == "starting" and status.active:
                state = "running"

        return {
            "state": state,
            "assessment_run": job.metadata.labels.get(
                "assessment-run"
            ),
            "active": status.active or 0,
            "succeeded": status.succeeded or 0,
            "failed": status.failed or 0,
            "started_at": (
                status.start_time.isoformat()
                if status.start_time else None
            ),
        }

    def stop(self, run_id):
        if not re.fullmatch(r"[a-f0-9]{32}", run_id):
            raise ValueError("Invalid assessment identifier")

        job = self.batch.read_namespaced_job(
            JOB_NAME, NAMESPACE
        )

        if job.metadata.labels.get("assessment-run") != run_id:
            raise AssessmentConflict(
                "Assessment identifier no longer matches"
            )

        self.batch.delete_namespaced_job(
            name=JOB_NAME,
            namespace=NAMESPACE,
            body=client.V1DeleteOptions(
                propagation_policy="Foreground",
                preconditions=client.V1Preconditions(
                    uid=job.metadata.uid
                ),
            ),
        )

        return {
            "state": "stopping",
            "assessment_run": run_id,
        }
