import hmac
import re

from functools import wraps

from flask import Flask, jsonify, request

from state import StateConflict
from execution import AssessmentConflict


def create_app(engine, token, max_base_users=10):

    if type(max_base_users) is not int or not 1 <= max_base_users <= 10:
        raise ValueError("Invalid deployment load limit")

    if not isinstance(token, str) or len(token) < 32:
        raise ValueError(
            "Controller token must contain at least 32 characters"
        )

    app = Flask(__name__)

    app.config["MAX_CONTENT_LENGTH"] = 4096

    def authenticated(handler):

        @wraps(handler)
        def wrapped(*args, **kwargs):

            supplied = request.headers.get(
                "Authorization", ""
            )

            expected = f"Bearer {token}"

            if not hmac.compare_digest(
                supplied.encode("utf-8"),
                expected.encode("utf-8"),
            ):
                return jsonify({
                    "error": "Unauthorized",
                }), 401

            return handler(*args, **kwargs)

        return wrapped

    @app.after_request
    def response_headers(response):

        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"

        return response

    @app.errorhandler(StateConflict)
    @app.errorhandler(AssessmentConflict)
    def conflict(error):

        return jsonify({
            "error": "Assessment conflict",
        }), 409

    @app.errorhandler(ValueError)
    def invalid_request(error):

        return jsonify({
            "error": "Invalid assessment parameters",
        }), 400

    @app.errorhandler(413)
    def oversized_request(error):

        return jsonify({
            "error": "Request too large",
        }), 413

    @app.get("/healthz")
    def health():

        return jsonify({
            "healthy": True,
        })

    @app.get("/readyz")
    def readiness():

        result = engine.health()

        healthy = result.get("healthy") is True

        return jsonify({
            "healthy": healthy,
        }), 200 if healthy else 503

    @app.get("/api/v1/status")
    @authenticated
    def status():

        return jsonify(engine.status())

    @app.get("/api/v1/history")
    @authenticated
    def history():

        return jsonify({
            "assessments": engine.history(),
        })

    @app.post("/api/v1/start")
    @authenticated
    def start():

        body = request.get_json(silent=True)

        if not isinstance(body, dict):
            raise ValueError("JSON object required")

        allowed = {
            "profile",
            "base_users",
            "recovery_minutes",
            "repeat",
            "max_cycles",
        }

        if set(body) - allowed:
            raise ValueError("Unexpected parameters")

        profile = body.get("profile")

        base_users = body.get("base_users", 1)

        recovery_minutes = body.get(
            "recovery_minutes", 10
        )

        repeat = body.get("repeat", False)

        max_cycles = body.get("max_cycles", 3)

        if profile not in ("normal", "1111"):
            raise ValueError("Invalid profile")

        if type(base_users) is not int or not 1 <= base_users <= max_base_users:
            raise ValueError("Invalid base users")

        if type(recovery_minutes) is not int or not 5 <= recovery_minutes <= 10:
            raise ValueError("Invalid recovery duration")

        if type(repeat) is not bool:
            raise ValueError("Invalid repeat setting")

        if type(max_cycles) is not int or not 1 <= max_cycles <= 3:
            raise ValueError("Invalid cycle limit")

        if engine.health().get("healthy") is not True:

            return jsonify({
                "error": "Controller not ready",
            }), 503

        result = engine.start_assessment(
            profile,
            base_users,
            recovery_minutes,
            repeat,
            max_cycles,
        )

        return jsonify(result), 202

    @app.post("/api/v1/stop")
    @authenticated
    def stop():

        body = request.get_json(silent=True)

        if not isinstance(body, dict):
            raise ValueError("JSON object required")

        if set(body) != {"assessment_run"}:
            raise ValueError("Invalid stop request")

        run_id = body["assessment_run"]

        if not isinstance(run_id, str) or not re.fullmatch(
            r"[a-f0-9]{32}", run_id
        ):
            raise ValueError("Invalid assessment identity")

        result = engine.stop_assessment(run_id)

        return jsonify(result), 202

    return app
