// convex/lib/html.ts
// Escaping for text that ends up inside HTML emails. User-controlled values (display names, etc.)
// must never be interpolated unescaped: an attacker-chosen name would otherwise become markup in an
// email delivered, under our branding, to a victim's inbox.

const ENTITIES: Record<string, string> = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#39;",
  "/": "&#x2F;",
  "`": "&#96;",
  "=": "&#61;",
};

/** Escapes every character that can open or close markup, attributes or entities. */
export function escapeHtml(input: unknown): string {
  return String(input ?? "").replace(/[&<>"'`=/]/g, (c) => ENTITIES[c]);
}

/** A display name made safe for emails: control chars removed, whitespace collapsed, bounded, escaped. */
export function safeDisplayNameForHtml(name: unknown, maxLength = 60): string {
  const cleaned = String(name ?? "")
    .replace(new RegExp("[\\u0000-\\u001f\\u007f-\\u009f\\u2028\\u2029\\u202a-\\u202e\\u2066-\\u2069]", "g"), " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maxLength);
  return escapeHtml(cleaned);
}
