import unittest

from unittest.mock import Mock

from api import create_app


class DeploymentLimitTests(unittest.TestCase):

    def setUp(self):

        self.engine = Mock()

        self.engine.health.return_value = {
            "healthy": True
        }

        self.engine.start_assessment.return_value = {
            "state": "starting"
        }

        self.token = "x" * 40

        self.app = create_app(
            self.engine,
            self.token,
            max_base_users=1,
        )

        self.client = self.app.test_client()

        self.headers = {
            "Authorization": f"Bearer {self.token}"
        }

    def start(self, users):

        return self.client.post(
            "/api/v1/start",
            headers=self.headers,
            json={
                "profile": "1111",
                "base_users": users,
            },
        )

    def test_initial_production_limit(self):

        result = self.start(1)

        self.assertEqual(
            result.status_code, 202
        )

    def test_excessive_production_load(self):

        result = self.start(2)

        self.assertEqual(
            result.status_code, 400
        )

        self.engine.start_assessment.assert_not_called()

    def test_invalid_deployment_limit(self):

        with self.assertRaises(ValueError):

            create_app(
                self.engine,
                self.token,
                max_base_users=100,
            )


if __name__ == "__main__":
    unittest.main()
