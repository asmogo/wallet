# Deterministic fixture recipes

Use these rules when an empty or normally reachable state cannot expose the
changed UI.

## Fixture contract

Use the same logical inputs in both revisions:

- fixed synthetic seed or test identity
- fixed IDs and ordering
- fixed timestamps/epoch
- fixed currency, locale, and amount values
- fixed mint capabilities and responses
- fixed transaction/payment states
- explicit success result before capture

Never use real wallet data, contacts, invoices, Lightning addresses, Nostr
keys, tokens, mint credentials, IP addresses, or balances.

## Prefer existing mechanisms

For iOS, inspect `IntegrationTestConfig.swift`, `CashuWalletUITests/UITestBase.swift`,
and the relevant UI tests. Reuse seeded-wallet launch modes, animation
suppression, accessibility identifiers, and local-mint environment variables.

For Android, prefer semantic UI navigation and normal onboarding for simple
empty-wallet states. Reuse Compose test harnesses for component-only visual
changes when a full app surface adds no value.

For network-backed flows, use only the repository's local CI test mints. Record
the fixture as a local synthetic service without publishing its host port or
machine address.

## Add a temporary debug fixture only when necessary

If no existing mechanism can reach the required state:

1. Design the smallest fixture adapter that calls real state classification and
   rendering code.
2. Add it only under each isolated worktree's debug, androidTest, or UI-test
   source set.
3. Apply equivalent logical inputs to both revisions, adapting only for API
   compatibility.
4. Keep a local patch and fixture-input JSON in the session directory.
5. Return or assert structured success before navigating.
6. Capture all rows.
7. Reverse the temporary patch in both worktrees.
8. Verify `git status --porcelain` is empty in both.

Never add fixture code to the active checkout. Never commit or publish it unless
the user separately asks to productize test infrastructure.

## Exercise real classification

A fixture must trigger the same conditions production UI uses. Examples:

- A self transaction must use the identity the app uses for ownership, not
  merely a matching display label.
- Pending, paid, expired, and failed states must use the real status enum and
  timing rules.
- A restored wallet must follow the restore boundary rather than injecting a
  post-restore screen flag.
- A privacy setting must be set through the same preference store consumed by
  the UI.

Avoid view-only mocks when the change is specifically about state-to-UI
mapping. Component harnesses are appropriate for isolated typography, spacing,
color, and control rendering.

## Keep state paired

Use clean install/reset for both revisions unless persistence is the subject of
the review. If preserving an app container or simulator state across installs,
prove that the logical records are unchanged and disclose the preservation
method.

Capture a control when it helps distinguish a regression from expected state:

- empty and populated history
- no mint and seeded test mint
- light and dark appearance
- normal and large text
- version-gated new path and fallback path

Do not add controls unrelated to the diff.
