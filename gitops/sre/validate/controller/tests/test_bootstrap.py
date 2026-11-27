import json
import unittest

from unittest.mock import Mock, patch

from kubernetes.client.exceptions import ApiException

from bootstrap import (
    initialize_state,
    build_engine,
    build_application,
)

from state import initial_state


class BootstrapTests(unittest.TestCase):

    def setUp(self):

        self.core = Mock()

        self.resource = Mock()

        self.resource.data = {
            "state.json": json.dumps(
                initial_state()
            )
        }

        self.core.read_namespaced_config_map.return_value = (
            self.resource
        )

    def test_existing_state_preserved(self):

        state = initialize_state(self.core)

        self.assertEqual(
            state["state"], "idle"
        )

        self.core.create_namespaced_config_map.assert_not_called()

    def test_running_state_preserved(self):

        state = initial_state()

        state.update({
            "state": "running",
            "assessment_run": "a" * 32,
        })

        self.resource.data = {
            "state.json": json.dumps(state)
        }

        result = initialize_state(self.core)

        self.assertEqual(
            result["state"], "running"
        )

        self.assertEqual(
            result["assessment_run"],
            "a" * 32,
        )

        self.core.create_namespaced_config_map.assert_not_called()

    def test_missing_state_requires_gitops(self):

        self.core.read_namespaced_config_map.side_effect = (
            ApiException(status=404)
        )

        with self.assertRaisesRegex(
            RuntimeError, "provisioned by GitOps"
        ):
            initialize_state(self.core)

        self.core.create_namespaced_config_map.assert_not_called()

    def test_state_api_failure_propagated(self):

        self.core.read_namespaced_config_map.side_effect = (
            ApiException(status=500)
        )

        with self.assertRaises(ApiException):
            initialize_state(self.core)

        self.core.create_namespaced_config_map.assert_not_called()

    def test_forbidden_state_access(self):

        self.core.read_namespaced_config_map.side_effect = (
            ApiException(status=403)
        )

        with self.assertRaises(ApiException):

            initialize_state(self.core)

        self.core.create_namespaced_config_map.assert_not_called()

    def test_missing_state_payload(self):

        self.resource.data = {}

        with self.assertRaises(RuntimeError):

            initialize_state(self.core)

    def test_corrupted_state_not_overwritten(self):

        self.resource.data = {
            "state.json": "invalid-json"
        }

        with self.assertRaises(ValueError):

            initialize_state(self.core)

        self.core.create_namespaced_config_map.assert_not_called()

    def test_missing_lifecycle_state(self):

        self.resource.data = {
            "state.json": "{}"
        }

        with self.assertRaises(RuntimeError):

            initialize_state(self.core)

    @patch("bootstrap.config.load_incluster_config")
    @patch("bootstrap.client")
    @patch("bootstrap.initialize_state")
    def test_real_constructor_composition(
        self,
        initialize,
        clients,
        load_config,
    ):

        engine = build_engine()

        load_config.assert_called_once()

        self.assertIsNotNone(
            engine.lifecycle.execution_gate
        )

        self.assertEqual(
            engine.interval, 5
        )

        clients.CoreV1Api.assert_called_once()
        clients.BatchV1Api.assert_called_once()
        clients.AppsV1Api.assert_called_once()
        clients.AutoscalingV2Api.assert_called_once()

        self.assertIsNone(engine.worker)

    @patch("bootstrap.build_engine")
    @patch.dict("os.environ", {}, clear=True)
    def test_missing_token_blocks_startup(
        self,
        build,
    ):

        with self.assertRaises(RuntimeError):

            build_application()

        build.assert_not_called()

    @patch("bootstrap.build_engine")
    @patch.dict(
        "os.environ",
        {
            "CAPSTONE_CONTROLLER_TOKEN":
                "x" * 40
        },
    )
    def test_application_wiring(self, build):

        app = build_application()

        self.assertIs(
            app.extensions[
                "capstone_assessment_engine"
            ],
            build.return_value,
        )

        result = app.test_client().get(
            "/healthz"
        )

        self.assertEqual(
            result.status_code, 200
        )


if __name__ == "__main__":
    unittest.main()
