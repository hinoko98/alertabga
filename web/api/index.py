"""Punto de entrada de la función Python en Vercel (y de uvicorn en desarrollo)."""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "_lib"))

from alertabga.main import create_app  # noqa: E402

app = create_app()
