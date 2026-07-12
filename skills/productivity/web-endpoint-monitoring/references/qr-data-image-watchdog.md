# QR Endpoint Returning HTML with Embedded Data Image

## Pattern

Some QR endpoints do not return `image/png` directly. They return a small HTML page such as:

```html
<img src="data:image/png;base64, iVBORw0KGgo...">
```

For these endpoints, a simple Content-Type check is insufficient because the response can be `text/html; charset=UTF-8` while still displaying a valid QR image in a browser.

## Healthy Criteria

Treat the response as healthy only when all are true:

1. HTTP status is 2xx.
2. Body does not contain configured error strings/codes.
3. HTML contains `data:image/(png|jpeg|jpg);base64, ...`.
4. Base64 decodes successfully.
5. Decoded bytes are plausibly an image (PNG signature `89 50 4E 47 0D 0A 1A 0A` or JPEG `FF D8 FF`).
6. Decoded image data is above a small minimum size threshold (for example >100 bytes) to reject empty placeholders.

## Alert Shape

Keep alerts concise:

```text
⚠️ QR画像チェックで異常を検出しました
時刻: <local ISO timestamp>
URL: <url>
理由: <predicate that failed>
HTTPステータス: <status>
Content-Type: <content type>
詳細: <trimmed sample or decode error>
```

## Notes

- Success should be silent in a script-only cron job.
- Print abnormal endpoint states and exit `0`; reserve non-zero exits for broken checker code.
- Parameterize URL and expected shape if you need to test a synthetic bad path without editing production code.
