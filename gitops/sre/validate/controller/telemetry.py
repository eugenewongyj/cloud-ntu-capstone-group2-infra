import math
import re
import time

import requests

from recovery import RecoveryObservation


PROMETHEUS_URL = (
    "http://kube-prometheus-stack-prometheus."
    "monitoring.svc.cluster.local:9090"
)


class TelemetryError(Exception):
    pass


class PrometheusTelemetry:

    def __init__(self, session=None):
        self.session = session or requests.Session()

    def query(self, expression, now):
        try:
            response = self.session.get(
                PROMETHEUS_URL + "/api/v1/query",
                params={
                    "query": expression,
                    "time": now,
                },
                timeout=3,
            )

            response.raise_for_status()
            payload = response.json()

            if payload["status"] != "success":
                raise TelemetryError("Prometheus query failed")

            if payload["data"]["resultType"] != "vector":
                raise TelemetryError("Unexpected result type")

            result = payload["data"]["result"]

            if not result:
                return None

            if len(result) != 1:
                raise TelemetryError("Expected one result")

            value = float(result[0]["value"][1])

            return value if math.isfinite(value) else None

        except (
            requests.RequestException,
            KeyError,
            ValueError,
            TypeError,
            IndexError,
        ) as exc:
            raise TelemetryError(str(exc)) from exc

    def recovery_observation(self, run_id, now=None):

        if not re.fullmatch(r"[a-f0-9]{32}", run_id):
            raise ValueError("Invalid assessment identifier")

        now = time.time() if now is None else now

        selector = (
            '{project="Capstone",'
            'namespace="retail-store",'
            f'assessment_run="{run_id}",'
            'assessment_phase="recovery"}'
        )

        latency = (
            "k6_capstone_product_listing_duration_p95"
            + selector
        )

        failure = "k6_http_req_failed_rate" + selector

        content = (
            "k6_capstone_product_listing_failed_rate"
            + selector
        )

        requests_total = "k6_http_reqs_total" + selector

        try:
            p95 = self.query(
                f"1000 * max({latency})", now
            )

            failure_rate = self.query(
                f"max({failure})", now
            )

            content_failure = self.query(
                f"max({content})", now
            )

            count = self.query(
                f"sum(increase({requests_total}[30s]))",
                now,
            )

            fresh = True

            for metric in (
                latency,
                failure,
                content,
                requests_total,
            ):
                timestamp = self.query(
                    f"min(timestamp({metric}))", now
                )

                if (
                    timestamp is None
                    or not 0 <= now - timestamp <= 15
                ):
                    fresh = False

            return RecoveryObservation(
                timestamp=now,
                p95_ms=p95,
                failure_rate=failure_rate,
                content_failure_rate=content_failure,
                request_count=max(0, int(count or 0)),
                fresh=fresh,
            )

        except TelemetryError:
            return RecoveryObservation(
                timestamp=now,
                p95_ms=None,
                failure_rate=None,
                content_failure_rate=None,
                request_count=0,
                fresh=False,
            )
