# E2E test execution and UI visual/DOM verification playbook

This document defines the automated test execution and manual visual/structural verification "skill" for the lolipop `v2.cgi` UI. By following this guide, agents can ensure that the UI renders properly, updates in real-time without duplicating elements, and has no legacy styling artifacts.

## Prerequisites
- Node.js version 24 installed via `mise`.
- Development database configured and server running locally (or ready to run tests using standard Playwright base config).

## Execution Guide

To run the E2E tests and refresh snapshots, execute the following script from the project root:
```bash
./scripts/run_e2e_verify.sh
```

This will run the Playwright tests and generate the following snapshot files in `tmp/snapshots/`:
- `1_pageA_logged_in.png` / `.html`
- `2_pageA_village_created.png` / `.html`
- `3_pageA_entered.png` / `.html`
- `4_pageB_entered.png` / `.html`
- `5_pageA_received_entry.png` / `.html`
- `6_pageB_received_say.png` / `.html`
- `7_pageA_received_reply.png` / `.html`
- `8_pageA_hover_anchor.png` / `.html`

---

## Verification Steps (For the AI Agent)

After executing the test, read the generated files using the `view_file` tool to verify the layout:

### Step 1: Check PNG Screenshots
Load the screenshot files (e.g., `view_file` on `tmp/snapshots/5_pageA_received_entry.png`, `6_pageB_received_say.png`, and `8_pageA_hover_anchor.png`) and confirm:
1. **No double rendering**: Real-time chats (like the test message and user entry notification) should be rendered exactly once per player.
2. **No legacy balloon artifacts**: The old speech bubble corner/tail images (white background artifacts) should not be visible. The chat box should be a modern styled container with clean borders and background.
3. **Correct avatar/profile pictures**: Characters should display their respective icons, and users (without a character) should fall back to the black avatar properly.
4. **Anchor Hover Popup**: Hovering over `>>4` link on Page A should display a beautiful tool-tip popup with a dark border, blur shadow, and compact nested card showing the target message (verified in `8_pageA_hover_anchor.png`).


### Step 2: Check HTML DOM Structure
Load the HTML sources (e.g., `view_file` on `tmp/snapshots/5_pageA_received_entry.html` and `6_pageB_received_say.html`) and check:
1. **Event IDs**: Elements should have unique `data-event-id` attributes to avoid duplicate insertions.
2. **First Action Box Prepending**: Verify that new message tables are prepended specifically before the first `.action_box` element rather than all `.action_box` elements.
3. **Announcements**: Ensure the `.announce` class wraps system messages like `花売り ヘレナ が集会所を訪れました。` and they are placed correctly within the chat container.

---

## Troubleshooting
- **jQuery Errors**: If real-time updating fails entirely, check the page's console log via Playwright configurations. Make sure jQuery `v3.7.1` is loaded for `v2.cgi` and that `.first()` is supported.
- **Database lock issues**: Ensure `ruby scripts/clean_db.rb` runs before each test run to ensure a clean slate.
