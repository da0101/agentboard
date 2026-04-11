<!--
Thanks for contributing to agentboard. Please fill every section below.
PRs that skip the security checklist will be asked to add it before review.
-->

## What does this PR do?

<!-- 1-3 short bullets. One sentence each. -->

-
-
-

## Type of change

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Template change (edits under `templates/`)
- [ ] Script change (edits to `bin/agentboard` or `templates/**/*.sh`)
- [ ] Docs (README, CONTRIBUTING, SECURITY, inline comments)

## Security checklist

> Every box below MUST be checked. CI enforces these rules — an unchecked
> box usually means the CI scanner will reject the PR anyway.

- [ ] No external URLs added to template files
- [ ] No network calls (`curl`, `wget`, `nc`, `netcat`, `/dev/tcp`) added to any file
- [ ] No instructions added that reference reading `.env`, `.ssh`, credentials, or API keys
- [ ] No base64-encoded strings or other obfuscated content
- [ ] No prompt-injection patterns ("ignore previous instructions", "act as", "you are now", etc.)
- [ ] Template changes have a plain-English explanation of what changed and why (see below)

## Template change explanation

<!--
If this PR touches any file under templates/, explain in plain English what
the change says and why it is needed. Example: "Adds a short paragraph to
ACTIVATE.md reminding the LLM to check for an .env.example file during
Stage 2 — fixes #42 where activation skipped env vars on projects with no
README."

If this PR does not touch templates/, write "N/A".
-->

## Testing

- [ ] Ran `agentboard init` locally in a fresh directory and verified the output
- [ ] Re-ran CI checks after any pushed fixups
- [ ] (If script change) exercised the affected command path manually

<!--
If your PR is a template-only change, at minimum run `agentboard init` in a
scratch directory and confirm the new content lands in the generated
.platform/ pack.
-->
