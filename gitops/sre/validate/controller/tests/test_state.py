import json
import unittest
from unittest.mock import create_autospec

from kubernetes import client
from kubernetes.client.exceptions import ApiException

from state import (
    AssessmentStateStore,
    StateConflict,
    initial_state,
    STATE_NAME,
    NAMESPACE,
)


class StateTests(unittest.TestCase):

    def setUp(self):
        self.core = create_autospec(
            client.CoreV1Api,
            instance=True,
            spec_set=True,
        )

        self.store = AssessmentStateStore(self.core)

        self.core.read_namespaced_config_map.return_value = (
            client.V1ConfigMap(
                metadata=client.V1ObjectMeta(
                    name=STATE_NAME,
                    namespace=NAMESPACE,
                    resource_version="100",
                ),
                data={
                    "state.json": json.dumps(initial_state())
                },
            )
        )

        self.core.patch_namespaced_config_map.return_value = (
            client.V1ConfigMap(
                metadata=client.V1ObjectMeta(
                    resource_version="101"
                )
            )
        )

    def test_initial_state(self):
        state = initial_state()

        self.assertEqual(state["state"], "idle")
        self.assertFalse(state["repeat"])
        self.assertFalse(state["stop_requested"])

    def test_read_shared_state(self):
        state, version = self.store.read()

        self.assertEqual(state["state"], "idle")
        self.assertEqual(version, "100")

        self.core.read_namespaced_config_map.assert_called_once_with(
            STATE_NAME, NAMESPACE
        )

    def test_versioned_write(self):
        state = initial_state()

        version = self.store.write(state, "100")

        body = (
            self.core.patch_namespaced_config_map
            .call_args.kwargs["body"]
        )

        self.assertEqual(
            body.metadata.resource_version, "100"
        )

        self.assertEqual(
            body.metadata.namespace, "monitoring"
        )

        self.assertEqual(version, "101")

    def test_concurrent_write_rejected(self):
        self.core.patch_namespaced_config_map.side_effect = (
            ApiException(status=409)
        )

        with self.assertRaises(StateConflict):
            self.store.write(initial_state(), "100")

    def test_missing_version_rejected(self):
        with self.assertRaises(ValueError):
            self.store.write(initial_state(), None)

        self.core.patch_namespaced_config_map.assert_not_called()

    def test_valid_transition(self):
        state, version = self.store.transition(
            {"idle"},
            {
                "state": "starting",
                "profile": "1111",
                "cycle": 1,
            },
        )

        self.assertEqual(state["state"], "starting")
        self.assertEqual(state["profile"], "1111")
        self.assertEqual(version, "101")

    def test_invalid_transition(self):
        with self.assertRaises(StateConflict):
            self.store.transition(
                {"running"},
                {"state": "stopping"},
            )

        self.core.patch_namespaced_config_map.assert_not_called()

    def test_missing_state_fails_closed(self):
        self.core.read_namespaced_config_map.side_effect = (
            ApiException(status=404)
        )

        with self.assertRaises(ApiException):
            self.store.read()


if __name__ == "__main__":
    unittest.main()
