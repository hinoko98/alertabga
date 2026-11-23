from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .auth import AuthError
from .config import get_settings
from .routers import health, historico, evidence, me, reports

PREFIX = "/api/py"


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title="AlertaBGA API",
        version="0.1.0",
        docs_url=f"{PREFIX}/docs",
        openapi_url=f"{PREFIX}/openapi.json",
        redoc_url=None,
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.allowed_origins,
        allow_methods=["GET", "POST", "PATCH", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "X-Device-Id"],
    )

    @app.exception_handler(AuthError)
    async def _auth_error(_: Request, __: AuthError) -> JSONResponse:
        return JSONResponse(status_code=401, content={"detail": "No autenticado"},
                            headers={"WWW-Authenticate": "Bearer"})

    app.include_router(health.router, prefix=PREFIX)
    app.include_router(me.router, prefix=PREFIX)
    app.include_router(historico.router, prefix=PREFIX)
    app.include_router(reports.router, prefix=PREFIX)
    app.include_router(evidence.router, prefix=PREFIX)
    return app
