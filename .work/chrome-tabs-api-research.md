# Chrome tabs API permission note

Checked 2026-10-04: Chrome for Developers, [Tabs API — Permissions and query filters](https://developer.chrome.com/docs/extensions/reference/api/tabs).

The `tabs` permission unlocks the sensitive `Tab` fields `url`, `pendingUrl`, `title`, and `favIconUrl` globally. Host permissions also allow reading and querying those same fields for matching tabs. The `tabs.query` URL filter is ignored only when the extension has neither `tabs` permission nor a host permission for the matching page. AMORA's YouTube-only host permissions therefore support its URL-scoped tab queries without requesting the broad `tabs` permission.
