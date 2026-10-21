"""Persist the Colab 0.7.4 assignment before its local state write."""

import json
import os
from pathlib import Path


handoff_file = os.environ.get("COLAB_GPU_HANDOFF_FILE")
handoff_session = os.environ.get("COLAB_GPU_HANDOFF_SESSION")
if handoff_file and handoff_session:
    from colab_cli.state import StateStore

    original_add = StateStore.add

    def add_with_handoff(store, session):
        if session.name == handoff_session:
            data = json.dumps(
                {"name": session.name, "session": session.model_dump(mode="json")}
            )
            path = Path(handoff_file)
            temporary = path.with_suffix(".tmp")
            with temporary.open("w", encoding="utf-8") as output:
                output.write(data)
                output.flush()
                os.fsync(output.fileno())
            os.replace(temporary, path)
        return original_add(store, session)

    StateStore.add = add_with_handoff
