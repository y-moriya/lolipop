const { test, expect } = require('@playwright/test');
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

// Helper to save screenshot and HTML content
async function saveSnapshot(page, label) {
  const snapshotDir = path.join(__dirname, '../tmp/snapshots');
  if (!fs.existsSync(snapshotDir)) {
    fs.mkdirSync(snapshotDir, { recursive: true });
  }
  const imgPath = path.join(snapshotDir, `${label}.png`);
  const htmlPath = path.join(snapshotDir, `${label}.html`);
  
  // Capture screenshot (fullPage to see everything)
  await page.screenshot({ path: imgPath, fullPage: true });
  
  // Capture HTML content
  const html = await page.content();
  fs.writeFileSync(htmlPath, html, 'utf8');
  console.log(`[Snapshot Saved] ${label} -> ${imgPath} and ${htmlPath}`);
}

test.describe('AIwolf Server E2E Tests for v2.cgi', () => {
  test.beforeEach(() => {
    try {
      execSync('ruby scripts/clean_db.rb');
    } catch (e) {
      console.error('Failed to clean database:', e.message);
    }
  });

  test('should login, create a village, enter, and receive chat messages in real-time via long-polling', async ({ browser }) => {
    // Array to collect unhandled browser exceptions and console errors
    const browserErrors = [];

    // Create contexts for User A and User B
    const contextA = await browser.newContext();
    const pageA = await contextA.newPage();
    
    // Listen to console logs and page errors on Page A
    pageA.on('console', msg => {
      if (msg.type() === 'error') {
        console.error(`[PAGE A CONSOLE ERROR] ${msg.text()}`);
        browserErrors.push(`[PAGE A CONSOLE ERROR] ${msg.text()}`);
      } else {
        console.log(`[PAGE A LOG] ${msg.text()}`);
      }
    });
    pageA.on('pageerror', exception => {
      console.error(`[PAGE A EXCEPTION] ${exception.stack || exception.message}`);
      browserErrors.push(`[PAGE A EXCEPTION] ${exception.message}`);
    });

    // 1. User A logins and creates a village
    await pageA.goto('/aiwolf/v2.cgi');
    await pageA.fill('input[name="userid"]', 'user_a');
    await pageA.fill('input[name="pass"]', 'password123');
    await pageA.click('input[value="ログイン"]');

    // Confirm successful login
    await expect(pageA.locator('input[value="ログアウト"]')).toBeVisible();
    await saveSnapshot(pageA, '1_pageA_logged_in');

    await expect(pageA.locator('a:has-text("村作成")')).toBeVisible();
    await pageA.click('a:has-text("村作成")');

    await pageA.fill('input[name="name"]', 'E2E Chat Village');
    await pageA.fill('input[name="entry_min"]', '4');
    await pageA.fill('input[name="entry_max"]', '16');
    await pageA.click('input[value="村作成"]');

    // Redirects back to the top page
    await expect(pageA).toHaveURL(/v2.cgi/);
    await saveSnapshot(pageA, '2_pageA_village_created');

    // Click the created village
    await pageA.click('a:has-text("E2E Chat Village")');
    await expect(pageA).toHaveURL(/vid=\d+/);

    // Enter the village (defaults to pid select and enter message)
    await pageA.fill('textarea[name="message"]', 'よろしくお願いします！');
    await pageA.click('input[value="エントリー"]');

    await expect(pageA.locator('text=user_a')).toBeVisible();
    await saveSnapshot(pageA, '3_pageA_entered');

    // 2. User B logins and enters the same village
    const contextB = await browser.newContext();
    const pageB = await contextB.newPage();

    // Listen to console logs and page errors on Page B
    pageB.on('console', msg => {
      if (msg.type() === 'error') {
        console.error(`[PAGE B CONSOLE ERROR] ${msg.text()}`);
        browserErrors.push(`[PAGE B CONSOLE ERROR] ${msg.text()}`);
      } else {
        console.log(`[PAGE B LOG] ${msg.text()}`);
      }
    });
    pageB.on('pageerror', exception => {
      console.error(`[PAGE B EXCEPTION] ${exception.stack || exception.message}`);
      browserErrors.push(`[PAGE B EXCEPTION] ${exception.message}`);
    });

    await pageB.goto('/aiwolf/v2.cgi');
    await pageB.fill('input[name="userid"]', 'user_b');
    await pageB.fill('input[name="pass"]', 'password456');
    await pageB.click('input[value="ログイン"]');

    await pageB.click('a:has-text("E2E Chat Village")');
    await expect(pageB).toHaveURL(/vid=\d+/);
    await pageB.fill('textarea[name="message"]', 'お邪魔します！');
    await pageB.click('input[value="エントリー"]');

    await expect(pageB.locator('text=user_b')).toBeVisible();
    await saveSnapshot(pageB, '4_pageB_entered');

    // Confirm User A receives the entry system message of User B in real-time
    await expect(pageA.locator('.announce').last()).toContainText('が集会所を訪れました。', { timeout: 20000 });
    await saveSnapshot(pageA, '5_pageA_received_entry');

    // 3. User A sends a message
    await pageA.fill('textarea[name="message"]', 'user_aからのテストメッセージです。');
    await pageA.click('input[type="submit"][value="発言"]');

    // Confirm User A sees their own message
    await expect(pageA.locator('.mes_say_body1').last()).toContainText('user_aからのテストメッセージです。');

    // 4. Confirm User B receives the message in real-time (without manual reload!)
    await expect(pageB.locator('.mes_say_body1').last()).toContainText('user_aからのテストメッセージです。', { timeout: 20000 });
    await saveSnapshot(pageB, '6_pageB_received_say');

    // 5. User B sends a reply with an anchor link (>>4 targets User A's test message)
    await pageB.fill('textarea[name="message"]', '>>4 user_bがリアルタイムで返信します。');
    await pageB.click('input[type="submit"][value="発言"]');

    // Confirm User A receives the reply in real-time
    const replyLocator = pageA.locator('.mes_say_body1').last();
    await expect(replyLocator).toContainText('user_bがリアルタイムで返信します。', { timeout: 20000 });
    await saveSnapshot(pageA, '7_pageA_received_reply');

    // Hover over the anchor link '>>4' on pageA
    const anchorLink = pageA.locator('a.say:has-text(">>4")');
    await expect(anchorLink).toBeVisible();
    await anchorLink.hover();

    // Verify anchor popup is displayed and contains the target message content
    const popup = pageA.locator('#anchor-popup');
    await expect(popup).toBeVisible();
    await expect(popup).toContainText('user_aからのテストメッセージです。');
    await saveSnapshot(pageA, '8_pageA_hover_anchor');

    await contextA.close();
    await contextB.close();

    // Assert that no unhandled exceptions or console errors occurred inside the browser!
    expect(browserErrors).toEqual([]);
  });
});
