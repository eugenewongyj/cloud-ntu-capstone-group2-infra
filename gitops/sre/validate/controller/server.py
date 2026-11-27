import logging

from gunicorn.app.base import BaseApplication

from bootstrap import build_application


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)


class ControllerServer(BaseApplication):

    def __init__(self):

        self.application = None

        super().__init__()

    def load_config(self):

        settings = {
            "bind": "0.0.0.0:8080",
            "workers": 1,
            "worker_class": "gthread",
            "threads": 4,
            "timeout": 120,
            "graceful_timeout": 45,
            "preload_app": False,
            "accesslog": "-",
            "errorlog": "-",
            "worker_exit": self.worker_exit,
        }

        for key, value in settings.items():

            self.cfg.set(key, value)

    def load(self):

        self.application = build_application()

        engine = self.application.extensions[
            "capstone_assessment_engine"
        ]

        engine.start_worker()

        return self.application

    def worker_exit(self, server, worker):

        if self.application is not None:

            engine = self.application.extensions[
                "capstone_assessment_engine"
            ]

            engine.shutdown(timeout=30)


if __name__ == "__main__":

    ControllerServer().run()
