"""Capstone product-listing load generator.

Set CAPSTONE_PRODUCT_PATH to the VERIFIED product listing path.
Run against an approved staging/test environment, not a production URL by default.
"""
import os
import random
from locust import HttpUser, LoadTestShape, between, task


def env_int(name: str, default: int) -> int:
    value = int(os.getenv(name, str(default)))
    if value <= 0:
        raise ValueError(f"{name} must be positive")
    return value


PRODUCT_PATH = os.getenv("CAPSTONE_PRODUCT_PATH", "")
if not PRODUCT_PATH.startswith("/") or PRODUCT_PATH.startswith("//"):
    raise ValueError("CAPSTONE_PRODUCT_PATH must be a relative absolute-path beginning with /")

BASE_USERS = env_int("BASE_USERS", 5)
SPAWN_RATE = env_int("SPAWN_RATE", 2)
PROFILE = os.getenv("LOAD_PROFILE", "baseline").lower()
if PROFILE not in {"baseline", "flash-demo", "flash-2h"}:
    raise ValueError("LOAD_PROFILE must be baseline, flash-demo, or flash-2h")


class ProductListingUser(HttpUser):
    wait_time = between(1, 3)

    @task
    def product_listing(self):
        # Group all product listing requests under one metric name.
        # Fail non-2xx responses and optionally enforce a simple response marker.
        with self.client.get(PRODUCT_PATH, name="product_listing", catch_response=True,
                             timeout=10) as response:
            if not 200 <= response.status_code < 300:
                response.failure(f"HTTP {response.status_code}")
            else:
                marker = os.getenv("CAPSTONE_EXPECT_TEXT", "")
                if marker and marker not in response.text:
                    response.failure("Expected product listing marker not found")
                else:
                    response.success()


class FlashSaleShape(LoadTestShape):
    """User concurrency stages, not guaranteed RPS multipliers.

    Baseline: 5m by default.
    Demo: 2m baseline, 3m 10x, 3m 20x, 2m recovery.
    2h: 5m baseline, 60m 10x, 60m 20x, 5m recovery.
    """
    def tick(self):
        if PROFILE == "baseline":
            stages = [(300, BASE_USERS)]
        elif PROFILE == "flash-demo":
            stages = [(120, BASE_USERS), (300, BASE_USERS * 10),
                      (480, BASE_USERS * 20), (600, BASE_USERS)]
        else:
            stages = [(300, BASE_USERS), (3900, BASE_USERS * 10),
                      (7500, BASE_USERS * 20), (7800, BASE_USERS)]
        elapsed = self.get_run_time()
        for cutoff, users in stages:
            if elapsed < cutoff:
                return (users, SPAWN_RATE)
        return None
