#!/usr/bin/env python3
"""Quiet HTML endpoint watchdog template.

Copy this file into ~/.hermes/scripts/, then set URL, EXPECTED_MARKER, and
(optional) EXPECTED_PATH. It prints nothing on success and a concise alert on
an endpoint failure. WATCH_URL can override URL for synthetic failure tests.
"""
from __future__ import annotations

import datetime as dt
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

URL = os.environ.get("WATCH_URL", "https://example.com/")
EXPECTED_MARKER = "Example Domain"
EXPECTED_PATH = "/"  # Set to "" to skip final-path validation.
LABEL = "example.com"
TIMEOUT = 20
MAX_BYTES = 2_000_000


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).astimezone().isoformat(timespec="seconds")


def alert(reason: str, *, status: int | str = "unknown", content_type: str = "", detail: str = "") -> None:
    lines = [
        f"⚠️ {LABEL} の監視で異常を検出しました",
        f"時刻: {now()}",
        f"URL: {URL}",
        f"理由: {reason}",
        f"HTTPステータス: {status}",
    ]
    if content_type:
        lines.append(f"Content-Type: {content_type}")
    if detail:
        lines.append(f"詳細: {detail[:500]}")
    print("\n".join(lines))


def main() -> int:
    req = urllib.request.Request(
        URL,
        headers={
            "User-Agent": "Hermes site watchdog/1.0",
            "Accept": "text/html,application/xhtml+xml;q=0.9,*/*;q=0.8",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as response:
            status = response.getcode()
            final_url = response.geturl()
            content_type = response.headers.get("Content-Type", "")
            body = response.read(MAX_BYTES)
    except urllib.error.HTTPError as exc:
        detail = exc.read(500).decode("utf-8", "replace") if hasattr(exc, "read") else repr(exc)
        alert("HTTPエラーを受信しました", status=exc.code, content_type=exc.headers.get("Content-Type", ""), detail=detail)
        return 0
    except Exception as exc:
        alert("アクセスできませんでした", detail=repr(exc))
        return 0

    if not 200 <= status < 400:
        alert("HTTPステータスが正常範囲ではありません", status=status, content_type=content_type)
        return 0
    if not body:
        alert("レスポンス本文が空です", status=status, content_type=content_type)
        return 0
    if "text/html" not in content_type.lower():
        alert("HTML以外のレスポンスを受信しました", status=status, content_type=content_type)
        return 0

    if EXPECTED_PATH:
        final_path = urllib.parse.urlparse(final_url).path.rstrip("/") or "/"
        expected_path = EXPECTED_PATH.rstrip("/") or "/"
        if final_path != expected_path:
            alert("別ページへリダイレクトされました", status=status, content_type=content_type, detail=f"final_url={final_url}")
            return 0

    text = body.decode("utf-8", "replace")
    if EXPECTED_MARKER and EXPECTED_MARKER not in text:
        alert("正常ページを示す文字列が見つかりません", status=status, content_type=content_type, detail=f"expected={EXPECTED_MARKER}; final_url={final_url}")
        return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
