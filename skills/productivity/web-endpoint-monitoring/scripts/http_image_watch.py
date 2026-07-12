#!/usr/bin/env python3
"""Generic quiet watchdog for direct image URLs or HTML pages with embedded data:image.

Usage:
  WATCH_URL='https://example.com/qr?text=hello' python3 http_image_watch.py

Optional env:
  WATCH_LABEL='QR画像チェック'
  WATCH_TIMEOUT='20'
  WATCH_MIN_BYTES='100'
  WATCH_ERROR_REGEX='error|エラー|failed|not found|500'

Success: prints nothing and exits 0.
Detected endpoint problem: prints an alert and exits 0.
Checker bug / invalid configuration: exits non-zero.
"""
from __future__ import annotations

import base64
import datetime as dt
import os
import re
import sys
import urllib.error
import urllib.request

URL = os.environ.get("WATCH_URL", "").strip()
LABEL = os.environ.get("WATCH_LABEL", "URL画像チェック")
TIMEOUT = int(os.environ.get("WATCH_TIMEOUT", "20"))
MIN_BYTES = int(os.environ.get("WATCH_MIN_BYTES", "100"))
ERROR_REGEX = os.environ.get(
    "WATCH_ERROR_REGEX",
    r"error(?:\\s*code)?|exception|failed|not\\s*found|forbidden|unauthorized|bad\\s*request|internal\\s+server\\s+error|エラー|エラーコード|例外|\\b(?:4\\d\\d|5\\d\\d)\\b",
)

PNG_SIG = b"\x89PNG\r\n\x1a\n"
JPEG_SIGS = (b"\xff\xd8\xff",)


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).astimezone().isoformat(timespec="seconds")


def looks_like_image(data: bytes) -> bool:
    return data.startswith(PNG_SIG) or any(data.startswith(sig) for sig in JPEG_SIGS)


def alert(reason: str, *, status: int | str = "unknown", content_type: str = "", detail: str = "") -> None:
    lines = [
        f"⚠️ {LABEL}で異常を検出しました",
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


def check_embedded_data_image(text: str) -> tuple[bool, str]:
    match = re.search(r"data:image/(png|jpeg|jpg);base64,\\s*([A-Za-z0-9+/=\\s]+)", text, re.I)
    if not match:
        return False, "HTML内に data:image の画像が見つかりません"
    try:
        raw = base64.b64decode(re.sub(r"\\s+", "", match.group(2)), validate=True)
    except Exception as exc:  # noqa: BLE001 - alert should include decode detail
        return False, f"data:image のbase64をデコードできません: {exc}"
    if len(raw) < MIN_BYTES:
        return False, f"data:image が小さすぎます: {len(raw)} bytes"
    if not looks_like_image(raw):
        return False, "data:image の中身がPNG/JPEG画像として認識できません"
    return True, ""


def main() -> int:
    if not URL:
        print("WATCH_URL is required", file=sys.stderr)
        return 2

    req = urllib.request.Request(URL, headers={"User-Agent": "Hermes endpoint watchdog/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            status = resp.getcode()
            content_type = resp.headers.get("Content-Type", "")
            data = resp.read(2_000_000)
    except urllib.error.HTTPError as exc:
        body = exc.read(1000).decode("utf-8", "replace") if hasattr(exc, "read") else ""
        alert("HTTPエラーコードを受信しました", status=exc.code, content_type=exc.headers.get("Content-Type", ""), detail=body)
        return 0
    except Exception as exc:  # noqa: BLE001 - convert endpoint/access failures to user alerts
        alert("アクセス自体に失敗しました", detail=repr(exc))
        return 0

    if not (200 <= status < 300):
        alert("HTTPステータスが2xxではありません", status=status, content_type=content_type, detail=data[:500].decode("utf-8", "replace"))
        return 0

    if content_type.lower().startswith("image/"):
        if len(data) >= MIN_BYTES and looks_like_image(data):
            return 0
        alert("Content-Typeは画像ですが、画像データとして不正または小さすぎます", status=status, content_type=content_type, detail=f"size={len(data)} bytes")
        return 0

    text = data.decode("utf-8", "replace")
    if ERROR_REGEX and re.search(ERROR_REGEX, text, re.I):
        alert("レスポンス本文にエラーらしき文字列/コードを検出しました", status=status, content_type=content_type, detail=text[:500])
        return 0

    ok, reason = check_embedded_data_image(text)
    if not ok:
        alert("画像が表示されるHTMLとして確認できません", status=status, content_type=content_type, detail=f"{reason}; body={text[:500]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
