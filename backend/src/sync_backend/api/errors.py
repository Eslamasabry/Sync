from typing import Any, cast

from fastapi import Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse


class ApiError(Exception):
    def __init__(
        self,
        *,
        code: str,
        message: str,
        status_code: int,
        details: dict[str, Any] | None = None,
        headers: dict[str, str] | None = None,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.status_code = status_code
        self.details = details or {}
        self.headers = headers or {}


def api_error_payload(
    *,
    code: str,
    message: str,
    details: dict[str, Any] | None = None,
) -> dict[str, Any]:
    return {
        "error": {
            "code": code,
            "message": message,
            "details": details or {},
        }
    }


async def api_error_handler(_: Request, exc: Exception) -> JSONResponse:
    api_exc = cast(ApiError, exc)
    return JSONResponse(
        status_code=api_exc.status_code,
        headers=api_exc.headers,
        content=api_error_payload(
            code=api_exc.code,
            message=api_exc.message,
            details=api_exc.details,
        ),
    )


async def request_validation_error_handler(
    _: Request,
    exc: Exception,
) -> JSONResponse:
    validation_exc = cast(RequestValidationError, exc)
    details = {
        "errors": [
            {
                "location": [str(part) for part in error["loc"]],
                "message": error["msg"],
                "type": error["type"],
            }
            for error in validation_exc.errors()
        ]
    }
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content=api_error_payload(
            code="request_validation_failed",
            message="The request payload is invalid",
            details=details,
        ),
    )


def not_found(code: str, message: str, details: dict[str, Any] | None = None) -> ApiError:
    return ApiError(
        code=code,
        message=message,
        status_code=status.HTTP_404_NOT_FOUND,
        details=details,
    )
