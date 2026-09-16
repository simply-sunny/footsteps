#!/usr/bin/env python3
"""Bundle repository Markdown for zero-fetch document switching."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
documents = {name.lower(): (root / f"{name}.md").read_text() for name in ("README", "PRIVACY", "ARCHITECTURE")}
(root / "docs/documents.js").write_text("window.FOOTSTEPS_DOCS = " + json.dumps(documents).replace("<", "\\u003c") + ";\n")
