# GitHub publishing

Read this reference only after the user explicitly authorizes uploading the
review images and posting to the target PR.

## Confirm scope

Restate the repository and PR number. Confirm that authorization covers:

1. creating or updating `refs/uploads/issues/<PR>` with image blobs
2. creating a PR conversation comment

These are GitHub writes even though the source branch is untouched. Do not
publish for a branch or commit target without a PR.

## Validate and sanitize

Run the manifest validator. Inspect the report and every image. Confirm that no
artifact contains:

- local paths, device serials, simulator UDIDs, hostnames, or private IPs
- real seeds, keys, tokens, contacts, balances, invoices, or payment data
- unrelated notifications, apps, browser content, or desktop chrome

Use only the images referenced by the validated manifest.

## Upload images

Dry-run first:

```sh
python3 .agents/skills/wallet-ui-visual-review/scripts/upload_pr_images.py \
  --repo OWNER/REPO --pr NUMBER \
  --manifest "<artifact-directory>/capture-manifest.json" --dry-run
```

After checking the exact file list, perform the repository write:

```sh
python3 .agents/skills/wallet-ui-visual-review/scripts/upload_pr_images.py \
  --repo OWNER/REPO --pr NUMBER \
  --manifest "<artifact-directory>/capture-manifest.json" --confirm-publish
```

The command returns the upload ref, commit SHA, image URLs, and Markdown. It
does not post the comment.

## Post the report

Use `assets/pr-comment-template.md`. Replace local image paths with returned
HTTPS URLs. Keep the stable marker:

```text
<!-- wallet-ui-visual-review:PR_NUMBER:AFTER_SHA -->
```

Prefer the connected GitHub app for the final comment when available; otherwise
use:

```sh
gh pr comment NUMBER --repo OWNER/REPO --body-file "<comment-file>"
```

Do not push images to the PR's source branch. Do not override Git author or
committer identity.

## Verify

Read the created comment back. Verify:

- the marker contains the expected PR and after SHA
- the exact number of expected image URLs is embedded
- every URL uses the upload commit returned by the uploader
- no local path or machine identifier appears

Return the verified comment URL. If verification fails, report it and do not
claim publishing succeeded.
