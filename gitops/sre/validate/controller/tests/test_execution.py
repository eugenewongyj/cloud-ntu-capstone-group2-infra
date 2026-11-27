import unittest
from pathlib import Path
from unittest.mock import create_autospec

import yaml
from kubernetes import client
from kubernetes.client.exceptions import ApiException

from execution import (
    AssessmentExecutor,
    AssessmentConflict,
    JOB_NAME,
    NAMESPACE,
    CONFIGMAP_NAME,
)


class ExecutionTests(unittest.TestCase):

    def setUp(self):
        self.batch = create_autospec(
            client.BatchV1Api,
            instance=True,
            spec_set=True,
        )

        self.core = create_autospec(
            client.CoreV1Api,
            instance=True,
            spec_set=True,
        )

        path = (
            Path(__file__).resolve().parents[2]
            / "k6/job-template.yaml"
        )

        self.template = yaml.safe_load(path.read_text())

        self.set_template()

        self.executor = AssessmentExecutor(
            self.batch,
            self.core,
        )

    def set_template(self):
        self.core.read_namespaced_config_map.return_value = (
            client.V1ConfigMap(
                metadata=client.V1ObjectMeta(
                    name=CONFIGMAP_NAME,
                    namespace=NAMESPACE,
                ),
                data={
                    "job-template.yaml":
                        yaml.safe_dump(self.template)
                },
            )
        )

    def created_job(self):
        return (
            self.batch.create_namespaced_job
            .call_args.kwargs["body"]
        )

    def test_normal_sale(self):
        result = self.executor.start("normal", 1, 10)

        self.assertEqual(result["profile"], "normal")

        job = self.created_job()

        self.assertEqual(
            job["metadata"]["name"], JOB_NAME
        )

        self.assertEqual(
            job["metadata"]["namespace"], "monitoring"
        )

        self.assertFalse(job["spec"]["suspend"])

        self.core.read_namespaced_config_map.assert_called_once_with(
            CONFIGMAP_NAME, NAMESPACE
        )

    def test_flash_sale(self):
        result = self.executor.start("1111", 1, 10)

        job = self.created_job()

        env = {
            item["name"]: item["value"]
            for item in job["spec"]["template"]["spec"]
            ["containers"][0]["env"]
        }

        self.assertEqual(env["LOAD_PROFILE"], "1111")
        self.assertEqual(env["BASE_USERS"], "1")
        self.assertEqual(
            env["ASSESSMENT_RUN"],
            result["assessment_run"],
        )

        self.assertEqual(
            env["TARGET_HOST"],
            "https://group2-shop.sctp-sandbox.com",
        )

        self.assertEqual(
            env["CAPSTONE_PRODUCT_PATH"], "/catalog"
        )

    def test_invalid_profile(self):
        with self.assertRaises(ValueError):
            self.executor.start("production")

        self.batch.create_namespaced_job.assert_not_called()

    def test_excessive_load(self):
        with self.assertRaises(ValueError):
            self.executor.start("1111", 11)

        self.batch.create_namespaced_job.assert_not_called()

    def test_invalid_recovery(self):
        with self.assertRaises(ValueError):
            self.executor.start("normal", 1, 30)

        self.batch.create_namespaced_job.assert_not_called()

    def test_concurrent_execution(self):
        self.batch.create_namespaced_job.side_effect = (
            ApiException(status=409)
        )

        with self.assertRaises(AssessmentConflict):
            self.executor.start("1111")

    def test_idle_status(self):
        self.batch.read_namespaced_job.side_effect = (
            ApiException(status=404)
        )

        self.assertEqual(
            self.executor.status(),
            {"state": "idle"},
        )

    def test_stale_stop_request(self):
        self.batch.read_namespaced_job.return_value = (
            client.V1Job(
                metadata=client.V1ObjectMeta(
                    name=JOB_NAME,
                    namespace=NAMESPACE,
                    uid="test-job-uid",
                    labels={"assessment-run": "b" * 32},
                ),
                status=client.V1JobStatus(active=1),
            )
        )

        with self.assertRaises(AssessmentConflict):
            self.executor.stop("a" * 32)

        self.batch.delete_namespaced_job.assert_not_called()

    def test_production_target_rejected(self):
        env = self.template["spec"]["template"]["spec"][
            "containers"
        ][0]["env"]

        for item in env:
            if item["name"] == "TARGET_HOST":
                item["value"] = (
                    "https://group2-retail.sctp-sandbox.com"
                )

        self.set_template()

        with self.assertRaises(ValueError):
            self.executor.start("normal")

        self.batch.create_namespaced_job.assert_not_called()

    def test_unauthorized_namespace_rejected(self):
        self.template["metadata"]["namespace"] = "retail-store"

        self.set_template()

        with self.assertRaises(ValueError):
            self.executor.start("normal")

        self.batch.create_namespaced_job.assert_not_called()


    def test_reserved_run_identifier(self):
        run_id = "c" * 32

        result = self.executor.start(
            "normal", 1, 10, run_id=run_id
        )

        job = self.created_job()
        pod = job["spec"]["template"]

        env = {
            item["name"]: item["value"]
            for item in pod["spec"]["containers"][0]["env"]
        }

        self.assertEqual(result["assessment_run"], run_id)

        self.assertEqual(
            job["metadata"]["labels"]["assessment-run"],
            run_id,
        )

        self.assertEqual(
            pod["metadata"]["labels"]["assessment-run"],
            run_id,
        )

        self.assertEqual(env["ASSESSMENT_RUN"], run_id)

    def test_invalid_reserved_identifier(self):
        with self.assertRaises(ValueError):
            self.executor.start(
                "normal", run_id="invalid"
            )

        self.batch.create_namespaced_job.assert_not_called()


if __name__ == "__main__":
    unittest.main()
