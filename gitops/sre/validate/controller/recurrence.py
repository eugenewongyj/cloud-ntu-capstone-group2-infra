import time
import uuid

from copy import deepcopy

from state import initial_state


COOLDOWN_SECONDS = 30

MAX_CYCLES = 3


def eligible_for_repeat(state):

    cycle = state.get("cycle")
    maximum = state.get("max_cycles")

    return (
        state.get("repeat") is True
        and state.get("stop_requested") is False
        and state.get("job_outcome") == "completed"
        and state.get("recovery_outcome") == "recovered"
        and state.get("current_health_confirmed") is True
        and state.get("telemetry_valid") is True
        and state.get("recovery_target_met") is True
        and type(cycle) is int
        and type(maximum) is int
        and 1 <= cycle < maximum <= MAX_CYCLES
    )


def next_assessment(state, now=None):

    now = time.time() if now is None else now

    if not eligible_for_repeat(state):
        raise ValueError("Assessment is not eligible")

    updated = initial_state()

    updated.update({
        "state": "starting",
        "assessment_run": uuid.uuid4().hex,
        "profile": state["profile"],
        "base_users": state["base_users"],
        "recovery_minutes": state["recovery_minutes"],
        "repeat": True,
        "cycle": state["cycle"] + 1,
        "max_cycles": state["max_cycles"],
        "reserved_at": now,
        "not_before": now + COOLDOWN_SECONDS,
        "history": deepcopy(state.get("history", [])),
        "last_completed_run": state["assessment_run"],
    })

    return updated
