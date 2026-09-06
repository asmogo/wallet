# Confirmations and errors

Simple action confirmations use `ActionConfirmationSheet` on both platforms,
including Generate new key, mint removal, history removal, key removal, wallet
deletion, Wallet Connect reset, and relay reset. The native sheet contains a
centered title, the consequence, Cancel, and a specific action label. Destructive
actions use the existing red primary button. Long content scrolls, and large
accessibility text stacks the actions. Cancel, Back, and drag dismissal never
commit an action. A confirmation can only submit once. On iOS, swipe buttons
that open a confirmation use a red tint without a destructive role, so the row
stays visible until removal is confirmed.

Confirm resetting relays only when custom relays would be discarded. Confirm
switching to an existing custom Nostr key on both platforms. iCloud enable and
disable retain their platform-specific backup disclosure in the same sheet style.
Payment review retains its amount, fee, and recipient layout.

Routine inline failures use supporting text with a semantic status icon. Android
now defaults to no filled container; an explicit container retains its matching
foreground colors. iOS uses readable supporting text and announces changes to an
existing notice. Field validation stays beside its field; App Lock failures stay
beside the toggle. System authentication remains unchanged.

Settings service failures use `ActionErrorMessages`, which names the operation
and offers a next step without exposing exception text, credentials, or storage
details. Lightning connection errors name the Lightning address service, rather
than the mint. Address status stays short, with the explanation shown once.
Key imports retain recognized invalid-key and duplicate-key guidance. Payment
outcome classification and retry rules remain owned by the wallet error mapper.

Verification covers malformed/raw service errors, key validation, cancellation,
repeat submission, large text, and light/dark screenshot previews. Live service
availability and payment settlement are separate from these UI checks.
