"""Standard kitchen recipe response envelope."""

from typing import Any, Dict


def success(
    data: Dict[str, Any],
    user_message: str = "Analysis completed successfully.",
    system_message: str = "Tier 4 analysis completed.",
    http_status: int = 200,
) -> Dict[str, Any]:
    return {
        "status": "SUCCESS",
        "http_status": http_status,
        "data": data,
        "user_message": user_message,
        "system_message": system_message,
    }


def error(
    status: str,
    http_status: int,
    user_message: str,
    system_message: str,
    data: Dict[str, Any] | None = None,
) -> Dict[str, Any]:
    return {
        "status": status,
        "http_status": http_status,
        "data": data or {},
        "user_message": user_message,
        "system_message": system_message,
    }
