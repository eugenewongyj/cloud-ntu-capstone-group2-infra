import unittest

from unittest.mock import Mock

from api import create_app
from state import StateConflict
from execution import AssessmentConflict


class ApiTests(unittest.TestCase):

    def setUp(self):

        self.engine = Mock()

        self.engine.health.return_value = {
            "healthy": True,
        }

        self.engine.status.return_value = {
            "state": "idle",
        }

        self.engine.history.return_value = []

        self.engine.start_assessment.return_value = {
            "state": "starting",
            "assessment_run": "a" * 32,
        }

        self.engine.stop_assessment.return_value = {
            "state": "stopping",
        }

        self.token = "test-token-" + "x" * 40

        self.headers = {
            "Authorization": f"Bearer {self.token}",
        }

        self.app = create_app(
            self.engine,
            self.token,
        )

        self.client = self.app.test_client()

    def post(self, endpoint, body):

        return self.client.post(
            endpoint,
            json=body,
            headers=self.headers,
        )

    def test_weak_token_rejected(self):

        with self.assertRaises(ValueError):
            create_app(self.engine, "short")

    def test_unauthenticated_status(self):

        result = self.client.get("/api/v1/status")

        self.assertEqual(result.status_code, 401)

    def test_wrong_token(self):

        result = self.client.get(
            "/api/v1/status",
            headers={
                "Authorization": "Bearer incorrect"
            },
        )

        self.assertEqual(result.status_code, 401)

    def test_unauthenticated_start(self):

        result = self.client.post(
            "/api/v1/start",
            json={"profile": "normal"},
        )

        self.assertEqual(result.status_code, 401)

        self.engine.start_assessment.assert_not_called()

    def test_authenticated_status(self):

        result = self.client.get(
            "/api/v1/status",
            headers=self.headers,
        )

        self.assertEqual(result.status_code, 200)

        self.assertEqual(
            result.json["state"], "idle"
        )

    def test_history(self):

        result = self.client.get(
            "/api/v1/history",
            headers=self.headers,
        )

        self.assertEqual(result.status_code, 200)

        self.assertEqual(
            result.json["assessments"], []
        )

    def test_normal_sale(self):

        result = self.post(
            "/api/v1/start",
            {"profile": "normal"},
        )

        self.assertEqual(result.status_code, 202)

        self.engine.start_assessment.assert_called_once_with(
            "normal", 1, 10, False, 3
        )

    def test_flash_sale_recurrence(self):

        result = self.post(
            "/api/v1/start",
            {
                "profile": "1111",
                "base_users": 1,
                "recovery_minutes": 5,
                "repeat": True,
                "max_cycles": 3,
            },
        )

        self.assertEqual(result.status_code, 202)

        self.engine.start_assessment.assert_called_once_with(
            "1111", 1, 5, True, 3
        )

    def test_invalid_profile(self):

        result = self.post(
            "/api/v1/start",
            {"profile": "smoke"},
        )

        self.assertEqual(result.status_code, 400)

        self.engine.start_assessment.assert_not_called()

    def test_target_override_rejected(self):

        result = self.post(
            "/api/v1/start",
            {
                "profile": "normal",
                "target_host": "https://example.com",
            },
        )

        self.assertEqual(result.status_code, 400)

    def test_excessive_users_rejected(self):

        result = self.post(
            "/api/v1/start",
            {
                "profile": "1111",
                "base_users": 100,
            },
        )

        self.assertEqual(result.status_code, 400)

    def test_invalid_recovery_rejected(self):

        result = self.post(
            "/api/v1/start",
            {
                "profile": "normal",
                "recovery_minutes": 2,
            },
        )

        self.assertEqual(result.status_code, 400)

    def test_excessive_cycles_rejected(self):

        result = self.post(
            "/api/v1/start",
            {
                "profile": "1111",
                "repeat": True,
                "max_cycles": 100,
            },
        )

        self.assertEqual(result.status_code, 400)

    def test_invalid_repeat_type(self):

        result = self.post(
            "/api/v1/start",
            {
                "profile": "normal",
                "repeat": "true",
            },
        )

        self.assertEqual(result.status_code, 400)

    def test_duplicate_start_conflict(self):

        self.engine.start_assessment.side_effect = (
            StateConflict()
        )

        result = self.post(
            "/api/v1/start",
            {"profile": "normal"},
        )

        self.assertEqual(result.status_code, 409)

    def test_existing_job_conflict(self):

        self.engine.start_assessment.side_effect = (
            AssessmentConflict()
        )

        result = self.post(
            "/api/v1/start",
            {"profile": "normal"},
        )

        self.assertEqual(result.status_code, 409)

    def test_stop(self):

        result = self.post(
            "/api/v1/stop",
            {"assessment_run": "a" * 32},
        )

        self.assertEqual(result.status_code, 202)

        self.engine.stop_assessment.assert_called_once_with(
            "a" * 32
        )

    def test_invalid_stop_identity(self):

        result = self.post(
            "/api/v1/stop",
            {"assessment_run": "invalid"},
        )

        self.assertEqual(result.status_code, 400)

        self.engine.stop_assessment.assert_not_called()

    def test_stale_stop_conflict(self):

        self.engine.stop_assessment.side_effect = (
            StateConflict()
        )

        result = self.post(
            "/api/v1/stop",
            {"assessment_run": "b" * 32},
        )

        self.assertEqual(result.status_code, 409)

    def test_health(self):

        result = self.client.get("/healthz")

        self.assertEqual(result.status_code, 200)

    def test_readiness(self):

        result = self.client.get("/readyz")

        self.assertEqual(result.status_code, 200)

    def test_not_ready(self):

        self.engine.health.return_value = {
            "healthy": False,
        }

        result = self.client.get("/readyz")

        self.assertEqual(result.status_code, 503)

    def test_start_blocked_when_not_ready(self):

        self.engine.health.return_value = {
            "healthy": False,
        }

        result = self.post(
            "/api/v1/start",
            {"profile": "normal"},
        )

        self.assertEqual(result.status_code, 503)

        self.engine.start_assessment.assert_not_called()

    def test_stop_available_when_not_ready(self):

        self.engine.health.return_value = {
            "healthy": False,
        }

        result = self.post(
            "/api/v1/stop",
            {"assessment_run": "a" * 32},
        )

        self.assertEqual(result.status_code, 202)

    def test_no_cache(self):

        result = self.client.get(
            "/api/v1/status",
            headers=self.headers,
        )

        self.assertEqual(
            result.headers["Cache-Control"],
            "no-store",
        )

    def test_oversized_request(self):

        result = self.post(
            "/api/v1/start",
            {"profile": "x" * 5000},
        )

        self.assertEqual(result.status_code, 413)


if __name__ == "__main__":
    unittest.main()
