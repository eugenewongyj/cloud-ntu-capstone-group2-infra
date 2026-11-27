import os
import unittest
from pathlib import Path

import yaml

INFRA = Path(__file__).resolve().parents[5]

APP = Path(os.environ.get(
    "CAPSTONE_APP_REF",
    "/tmp/capstone-group2-app-contract",
))

VALIDATE = INFRA / "gitops/sre/validate"


def read_yaml(path):
    return yaml.safe_load(path.read_text())


class RepositoryContractTests(unittest.TestCase):

    def setUp(self):
        self.ui = read_yaml(
            INFRA / "gitops/app/apps/ui.yaml"
        )

        self.catalog = read_yaml(
            INFRA / "gitops/app/apps/catalog.yaml"
        )

        self.job = read_yaml(
            VALIDATE / "k6/job-template.yaml"
        )

        self.pod = self.job["spec"]["template"]["spec"]

        self.env = {
            item["name"]: item["value"]
            for item in self.pod["containers"][0]["env"]
        }

    def test_application_repository(self):
        expected = (
            "https://github.com/eugenewongyj/"
            "cloud-ntu-capstone-group2-app.git"
        )

        for application in (self.ui, self.catalog):
            self.assertEqual(
                application["spec"]["source"]["repoURL"],
                expected,
            )

    def test_helm_chart_paths(self):
        for application, expected in (
            (self.ui, "src/ui/chart"),
            (self.catalog, "src/catalog/chart"),
        ):
            actual = application["spec"]["source"]["path"]

            self.assertEqual(actual, expected)
            self.assertTrue(
                (APP / actual / "Chart.yaml").is_file()
            )

    def test_production_namespace(self):
        for application in (self.ui, self.catalog):
            self.assertEqual(
                application["spec"]["destination"]["namespace"],
                "retail-store",
            )

    def test_production_host(self):
        values = self.ui["spec"]["source"]["helm"]["valuesObject"]
        hosts = values["ingress"]["hosts"]

        self.assertIn(
            "group2-retail.sctp-sandbox.com",
            hosts,
        )

        self.assertEqual(
            self.env["TARGET_HOST"],
            "https://group2-shop.sctp-sandbox.com",
        )

        self.assertNotEqual(
            self.env["TARGET_HOST"],
            "https://group2-retail.sctp-sandbox.com",
        )

    def test_application_catalog_route(self):
        source = (
            APP / "src/ui/src/main/java/com/amazon/sample/"
            "ui/web/CatalogController.java"
        ).read_text()

        self.assertIn('@RequestMapping("/catalog")', source)
        self.assertIn('@GetMapping("")', source)

        self.assertEqual(
            self.env["CAPSTONE_PRODUCT_PATH"],
            "/catalog",
        )

    def test_catalog_response_marker(self):
        template = (
            APP / "src/ui/src/main/resources/"
            "templates/catalog.html"
        ).read_text()

        self.assertIn(
            self.env["CAPSTONE_EXPECT_TEXT"],
            template,
        )

    def test_ui_catalog_dependency(self):
        values = self.ui["spec"]["source"]["helm"]["valuesObject"]

        self.assertEqual(
            values["app"]["endpoints"]["catalog"],
            "http://catalog:80",
        )

    def test_production_hpa_contract(self):
        for application in (self.ui, self.catalog):
            values = application["spec"]["source"]["helm"]["valuesObject"]
            hpa = values["autoscaling"]

            self.assertTrue(hpa["enabled"])
            self.assertEqual(hpa["minReplicas"], 2)
            self.assertEqual(hpa["maxReplicas"], 6)
            self.assertEqual(
                hpa["targetCPUUtilizationPercentage"], 70
            )

    def test_prometheus_remote_write(self):
        values = read_yaml(
            INFRA / "gitops/sre/values/prometheus.yaml"
        )

        self.assertTrue(
            values["prometheus"]["prometheusSpec"]
            ["enableRemoteWriteReceiver"]
        )

        self.assertEqual(
            self.env["K6_PROMETHEUS_RW_SERVER_URL"],
            "http://kube-prometheus-stack-prometheus."
            "monitoring.svc.cluster.local:9090/api/v1/write",
        )

    def test_sre_namespace_permission(self):
        project = read_yaml(
            INFRA / "gitops/sre/projects/sre-project.yaml"
        )

        namespaces = {
            item["namespace"]
            for item in project["spec"]["destinations"]
        }

        self.assertIn("monitoring", namespaces)

        self.assertEqual(
            self.job["metadata"]["namespace"],
            "monitoring",
        )

    def test_job_execution_safety(self):
        spec = self.job["spec"]

        self.assertTrue(spec["suspend"])
        self.assertEqual(spec["parallelism"], 1)
        self.assertEqual(spec["completions"], 1)
        self.assertEqual(spec["backoffLimit"], 0)

        self.assertFalse(
            self.pod["automountServiceAccountToken"]
        )

        self.assertEqual(
            self.pod["restartPolicy"],
            "Never",
        )

    def test_gitops_workload_packaging(self):
        config = read_yaml(
            VALIDATE / "k6/kustomization.yaml"
        )

        generator = next(
            item for item in config["configMapGenerator"]
            if item["name"] == "capstone-k6-workload"
        )

        self.assertIn(
            "product-listing.js",
            generator["files"],
        )

        self.assertIn(
            "job-template.yaml",
            generator["files"],
        )


if __name__ == "__main__":
    unittest.main()
