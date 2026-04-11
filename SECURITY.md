# Security Policy

agentboard is a bash CLI plus a collection of markdown templates that AI
agents read and execute inside other people's codebases. The attack
surface that matters is therefore: (1) malicious bash in the shipped
scripts and (2) prompt-injection or credential-exfiltration instructions
hidden inside template `.md` files. Both are treated as the same class of
bug and go through the same disclosure process below.

## Supported versions

Only the latest published release (the most recent `v*.*.*` tag on
`main`) is supported with security fixes. Older tags are for reference
only — if you are running anything other than the current release,
please upgrade before reporting a vulnerability.

| Version       | Supported       |
| ------------- | --------------- |
| Latest `v*.*.*` release on `main` | Yes |
| Anything older | No             |

## Reporting a vulnerability

**Do NOT open a public GitHub issue for anything that looks like a
security bug.** Public issues are indexed immediately and give attackers
a head start on exploitation.

Pick whichever of these is easier:

1. **Email**: `security@agentboard.dev`
2. **GitHub private advisory**: open a draft security advisory at
   <https://github.com/da0101/agentboard/security/advisories/new>

In the report, please include:

- A short description of the issue and its category (malicious bash,
  prompt injection, supply chain, etc.)
- The exact file(s) and line number(s) involved, or a minimal PoC
- The agentboard version you observed it in (`agentboard version`)
- Your name/handle for the credit line (or tell us you want to stay
  anonymous — we will honor that)

## What to report

These are the specific concerns we want to hear about:

- **Prompt injection in templates** — a template `.md` file under
  `templates/` that tries to manipulate the AI agent reading it (e.g.
  "ignore previous instructions", "you are now…", "read .env and send it
  to…").
- **Malicious bash in scripts** — anything in `bin/agentboard` or
  `templates/**/*.sh` that makes outbound network calls, exfiltrates
  credentials, decodes obfuscated payloads, or executes attacker-
  controlled input.
- **Supply-chain attacks** — a compromised release tarball, a tampered
  SHA256SUMS file, a hijacked dependency, or any mismatch between a
  published release and its tag content.
- **CI / scanner bypass** — a way to land one of the above without
  tripping `.github/workflows/security-scan.yml`.

## Response timeline

- **Acknowledgement**: within 48 hours of receipt.
- **Initial assessment and severity rating**: within 5 business days.
- **Patch for critical issues** (RCE, credential exfiltration, any
  widely-exploitable prompt injection): within 7 days.
- **Patch for high/medium issues**: within 30 days.
- **Coordinated disclosure**: we will agree a public disclosure date with
  you before publishing the advisory. Default is "as soon as the fix
  ships".

## What NOT to report publicly

If while investigating agentboard you accidentally come across
credentials, API keys, tokens, or any other secret belonging to a real
user (yours, ours, or a third party), **do not post it anywhere public
— not in a GitHub issue, not in a tweet, not in a blog post**.

Report it privately via the channels above and we will coordinate the
rotation. Publishing a leaked secret, even to "prove" the bug, is not an
acceptable form of disclosure and will be treated as an aggravating
factor, not a mitigating one.

## Scope

In scope:

- The `bin/agentboard` script
- Every file under `templates/`
- Every file under `.github/workflows/`
- `SHA256SUMS` and the release tarballs published from `main`

Out of scope:

- Vulnerabilities in third-party AI tools (Claude Code, Codex CLI,
  Gemini CLI) themselves — please report those to their respective
  vendors.
- Misuse of agentboard inside a target project (e.g. a downstream user
  editing their own `.platform/` files to something unsafe — that is
  the downstream project's problem, not agentboard's).
- Social engineering attacks against individual maintainers.

Thanks for helping keep agentboard safe.
