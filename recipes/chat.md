# Proximity chat

Code: [`snippets/chat.rs`](snippets/chat.rs).

* `say(text)`: checks admission, rejects empty, control-character or overlong text (200 chars), rate-limits
  each player to one message per 0.5 s (private `chat_rate` table), and stamps the sender's current cell.
* `chat_message` is public and indexed by cell. Clients subscribe by cell, exactly like `entity_transform`
  (see `aoi-subscriptions.md`), so chat is local for free. For global chat, add a `channel` column and subscribe `WHERE channel = 0`.
* Retention: the table keeps the newest 500 messages. Each insert deletes the row that fell off the end, so the cost is constant.
* The sender name is copied in when the message is sent, so renames do not rewrite history.

**Checked (2026-10-31):** Two TS clients. Bob saw `Alice: hello`. Alice's second message within 0.5 s was
rejected with `slow down`.

**Private messages:** add a private `whisper` table with `to`/`from`, and expose it through a view that returns
rows where `to == ctx.sender() || from == ctx.sender()`. Never use a public table filtered on the client.

**Moderation:** add a `muted` table that `say` checks. Writing it should be operator-only (`operator-role.md`).
