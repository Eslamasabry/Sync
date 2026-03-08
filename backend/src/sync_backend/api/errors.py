from typing import Any, cast

from fastapi import Request, status
from fastapi.responses import JSONResponse


class ApiError(Exception):
    def __init__(
        self,
        *,
        code: str,
        message: str,
        status_code: int,
        details: dict[str, Any] | None = None,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.status_code = status_code
        self.details = details or {}


async def api_error_handler(_: Request, exc: Exception) -> JSONResponse:
    api_exc = cast(ApiError, exc)
    return JSONResponse(
        status_code=api_exc.status_code,
        content={
            "error": {
                "code": api_exc.code,
                "message": api_exc.message,
                "details": api_exc.details,
            }
        },
    )


def not_found(code: str, message: str, details: dict[str, Any] | None = None) -> ApiError:
    return ApiError(
        code=code,
        message=message,
        status_code=status.HTTP_404_NOT_FOUND,
        details=details,
    )
