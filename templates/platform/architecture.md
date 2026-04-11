# {{PROJECT_NAME}} — Architecture

Last updated: {{TODAY}}

> {{DESCRIPTION}}

---

## 1. What this system does

_1-2 paragraphs explaining the system from a user's perspective and a technical perspective._

**Who uses it:** _end users_
**Who deploys it:** _dev team / CI / manual_
**Hosting target:** _AWS / GCP / Firebase / bare metal / App Store / Play Store / desktop / …_

## 2. High-level components

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Component A │ ──→ │  Component B │ ──→ │  Component C │
└──────────────┘     └──────────────┘     └──────────────┘
```

_Replace the diagram with the real component topology. Keep it to one screen._

## 3. Tech stack (summary)

| Layer | Choice | Notes |
|---|---|---|
| Language(s) | _…_ | |
| Framework(s) | _…_ | |
| Build tool(s) | _…_ | |
| Data store(s) | _…_ | |
| Hosting | _…_ | |
| CI/CD | _…_ | |

Per-stack conventions live in `conventions/{stack}.md`.

## 4. Data flow

_Explain how data moves through the system. Where it originates, where it's persisted, where it's read, where it's displayed._

## 5. Auth model

_Explain the auth boundary. Who can do what. Where permissions are checked (at the gateway? at the service? at the view?)._

See `conventions/permissions.md` for the permission model and `conventions/security.md` for auth details.

## 6. External services

| Service | What it's used for | Where the secret lives |
|---|---|---|
| _e.g. Stripe_ | _payments_ | _env var / secret manager_ |

## 7. Deploy topology

_Where each component lives in production. Environments (dev / staging / prod). How they're promoted._

See `conventions/deployment.md` for the deploy + rollback playbook.

## 8. Cross-component invariants

The things that must stay true as the system evolves. Breaking any of these is a hard fail.

1. _Invariant 1_
2. _Invariant 2_
3. _Invariant 3_

## 9. Known architectural debt

| Area | Issue | Planned fix |
|---|---|---|
| _e.g. Module X_ | _Issue_ | _Plan or "deferred"_ |
