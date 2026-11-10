# Security policy

This kit supplies reference patterns, not a security certification. No supported production release window or response-time promise is currently established. Check the exact revision you deploy and retest after changes.

## Report a vulnerability privately

Use the repository's **Security | Report a vulnerability** option if maintainers have enabled private vulnerability reporting. If it is unavailable, ask a maintainer for a private reporting route without posting exploit details publicly. Do not include credentials, personal data, private server addresses, or live tokens in issues.

Include the affected commit and template, toolchain versions, the violated authority/privacy boundary, and a minimal sanitized reproduction. Explain whether the exploit needs an ordinary client, operator identity, or server access. Keep active-system testing within your authorization.

## Review before exposure

Follow [the security guide](docs/wiki/Security.md) and [stdb-security-review](skills/stdb-security-review/SKILL.md). At minimum test scheduler-call rejection, forged identity/position rejection, admission after revocation, private-table visibility, and reconnect behavior. Public tables can be read by any authorized subscriber; AOI filtering is a bandwidth choice, not confidentiality.

Development defaults include open admission and local HTTP endpoints. Make deployment-specific decisions about access, transport, backups, rate limits, logs, and operator identities before an external playtest. Preserve license notices when distributing the kit or vendored dependencies.
