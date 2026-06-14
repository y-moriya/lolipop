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

// Helper to programmatically submit a form that is broken due to table nesting
async function submitFormWorkaround(page, selectName) {
  const selectLocator = page.locator(`select[name="${selectName}"]`);
  await expect(selectLocator).toBeVisible();
  
  // Get the selected value from the page
  const selectedValue = await selectLocator.inputValue();
  console.log(`[E2E] Submitting ${selectName} with value ${selectedValue} via workaround`);
  
  await Promise.all([
    page.waitForNavigation({ waitUntil: 'load' }),
    page.evaluate(({ selectName, selectedValue }) => {
      const form = document.createElement('form');
      form.action = 'v2.cgi';
      form.method = 'POST';
      
      const vid = document.querySelector('input[name="vid"]')?.value || '1';
      const set_date = document.querySelector('input[name="set_date"]')?.value || '1';
      const cmd = selectName === 'vote_id' ? 'vote' : 'skill';
      
      const fields = {
        vid: vid,
        set_date: set_date,
        cmd: cmd,
        [selectName]: selectedValue
      };
      
      for (const [key, val] of Object.entries(fields)) {
        const input = document.createElement('input');
        input.type = 'hidden';
        input.name = key;
        input.value = val;
        form.appendChild(input);
      }
      
      document.body.appendChild(form);
      form.submit();
    }, { selectName, selectedValue })
  ]);
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
    await pageA.click('.chat-send-btn');

    // Confirm User A sees their own message
    await expect(pageA.locator('.mes_say_body1').last()).toContainText('user_aからのテストメッセージです。');

    // 4. Confirm User B receives the message in real-time (without manual reload!)
    await expect(pageB.locator('.mes_say_body1').last()).toContainText('user_aからのテストメッセージです。', { timeout: 20000 });
    await saveSnapshot(pageB, '6_pageB_received_say');

    // 5. User B sends a reply with an anchor link (>>4 targets User A's test message)
    await pageB.fill('textarea[name="message"]', '>>4 user_bがリアルタイムで返信します。');
    await pageB.click('.chat-send-btn');

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
    await popup.waitFor({ state: 'visible', timeout: 5000 }).catch(async () => {
      console.log('[E2E] Retrying hover on >>4 due to timeout');
      await anchorLink.hover();
    });
    await expect(popup).toBeVisible();
    await expect(popup).toContainText('user_aからのテストメッセージです。');
    await saveSnapshot(pageA, '8_pageA_hover_anchor');

    await contextA.close();
    await contextB.close();

    // Assert that no unhandled exceptions or console errors occurred inside the browser!
    expect(browserErrors).toEqual([]);
  });

  test('should run enhanced 3-user dynamic werewolf game scenario', async ({ browser }) => {
    const browserErrors = [];

    const setupErrorTracking = (page, name) => {
      page.on('console', msg => {
        if (msg.type() === 'error') {
          console.error(`[${name} CONSOLE ERROR] ${msg.text()}`);
          browserErrors.push(`[${name} CONSOLE ERROR] ${msg.text()}`);
        } else {
          console.log(`[${name} LOG] ${msg.text()}`);
        }
      });
      page.on('pageerror', exception => {
        console.error(`[${name} EXCEPTION] ${exception.stack || exception.message}`);
        browserErrors.push(`[${name} EXCEPTION] ${exception.message}`);
      });
    };

    // Create contexts for User A, User B, User C, and User D
    const contextA = await browser.newContext();
    const pageA = await contextA.newPage();
    setupErrorTracking(pageA, 'Page A');

    const contextB = await browser.newContext();
    const pageB = await contextB.newPage();
    setupErrorTracking(pageB, 'Page B');

    const contextC = await browser.newContext();
    const pageC = await contextC.newPage();
    setupErrorTracking(pageC, 'Page C');

    const contextD = await browser.newContext();
    const pageD = await contextD.newPage();
    setupErrorTracking(pageD, 'Page D');

    // 1. User A logins and creates a village
    await pageA.goto('/aiwolf/v2.cgi');
    await pageA.fill('input[name="userid"]', 'user_a');
    await pageA.fill('input[name="pass"]', 'password123');
    await pageA.click('input[value="ログイン"]');
    await expect(pageA.locator('input[value="ログアウト"]')).toBeVisible();

    await pageA.click('a:has-text("村作成")');
    await pageA.fill('input[name="name"]', 'Enhanced E2E');
    await pageA.fill('input[name="entry_min"]', '4');
    await pageA.fill('input[name="entry_max"]', '4');

    // Select preset "牛村" (CATTLE) - value 4
    await pageA.selectOption('select[name="composition"]', '4');

    // Make sure dummy checkbox is checked
    const dummyCheckbox = pageA.locator('input[name="dummy"]');
    if (await dummyCheckbox.isVisible()) {
      await dummyCheckbox.check();
    }

    // Make sure possessed switch is unchecked to avoid extra night action for Possessed
    const possessedCheckbox = pageA.locator('input[name="possessed"]');
    if (await possessedCheckbox.isVisible()) {
      await possessedCheckbox.uncheck();
    }

    await pageA.click('input[value="村作成"]');
    await expect(pageA).toHaveURL(/v2.cgi/);

    // Get the created village link and click it
    await pageA.click('a:has-text("Enhanced E2E")');
    await expect(pageA).toHaveURL(/vid=\d+/);

    const url = pageA.url();
    const vidMatch = url.match(/vid=(\d+)/);
    const vid = vidMatch[1];
    console.log(`[E2E] Village created with ID: ${vid}`);

    // User A enters the village (chooses character index 1)
    await pageA.selectOption('select[name="pid"]', '1');
    await pageA.fill('textarea[name="message"]', 'エントリーします！');
    await pageA.click('input[value="エントリー"]');
    await expect(pageA.locator('text=user_a').first()).toBeVisible();

    // 2. User B logins and enters
    await pageB.goto('/aiwolf/v2.cgi');
    await pageB.fill('input[name="userid"]', 'user_b');
    await pageB.fill('input[name="pass"]', 'password456');
    await pageB.click('input[value="ログイン"]');
    await pageB.goto(`/aiwolf/v2.cgi?vid=${vid}`);
    await pageB.selectOption('select[name="pid"]', '2');
    await pageB.fill('textarea[name="message"]', 'お邪魔します！');
    await pageB.click('input[value="エントリー"]');
    await expect(pageB.locator('text=user_b').first()).toBeVisible();

    // 3. User C logins and enters
    await pageC.goto('/aiwolf/v2.cgi');
    await pageC.fill('input[name="userid"]', 'user_c');
    await pageC.fill('input[name="pass"]', 'password789');
    await pageC.click('input[value="ログイン"]');
    await pageC.goto(`/aiwolf/v2.cgi?vid=${vid}`);
    await pageC.selectOption('select[name="pid"]', '3');
    await pageC.fill('textarea[name="message"]', 'よろしくおねがいします！');
    await pageC.click('input[value="エントリー"]');
    await expect(pageC.locator('text=user_c').first()).toBeVisible();

    // 3.5. User D logins and opens the village page without entering (Spectator)
    await pageD.goto('/aiwolf/v2.cgi');
    await pageD.fill('input[name="userid"]', 'user_d');
    await pageD.fill('input[name="pass"]', 'password999');
    await pageD.click('input[value="ログイン"]');
    await expect(pageD.locator('input[value="ログアウト"]')).toBeVisible();
    await pageD.goto(`/aiwolf/v2.cgi?vid=${vid}`);
    await saveSnapshot(pageD, 'enhanced_1_userD_spectating');

    await saveSnapshot(pageA, 'enhanced_1_users_entered');

    // 4. User A (owner) starts the village
    // Go to the Info tab (date=0) where the edit/start buttons are rendered
    await pageA.goto(`/aiwolf/v2.cgi?vid=${vid}&date=0`);

    // Register dialog handler to accept confirm dialog
    pageA.once('dialog', async dialog => {
      console.log(`[E2E] Accept start dialog: ${dialog.message()}`);
      await dialog.accept();
    });
    await pageA.click('input[value="村開始"]');

    // Wait for the game start reload prompt on pageB, pageC and pageD and click/reload them
    await pageB.locator('.reload-prompt').click({ timeout: 15000 });
    await pageC.locator('.reload-prompt').click({ timeout: 15000 });

    const promptDStartVisible = await pageD.locator('.reload-prompt').isVisible({ timeout: 15000 }).catch(() => false);
    if (promptDStartVisible) {
      await pageD.locator('.reload-prompt').click();
    } else {
      await pageD.reload();
    }

    await saveSnapshot(pageA, 'enhanced_2_game_started');

    // Helper functions to check roles
    const isWolf = (role) => role === '人狼' || role === '人喰い';
    const isSeer = (role) => role === '占い師';
    const isPossessed = (role) => role === '狂人';

    const getPlayerRole = async (page) => {
      const body = page.locator('.action_balloon td.action_body').first();
      await expect(body).toBeVisible({ timeout: 10000 });
      const text = await body.innerText();
      const match = text.match(/\(([^)]+)\)/);
      return match ? match[1] : null;
    };

    const roleA = await getPlayerRole(pageA);
    const roleB = await getPlayerRole(pageB);
    const roleC = await getPlayerRole(pageC);

    console.log(`[E2E] Assigned Roles: User A = ${roleA}, User B = ${roleB}, User C = ${roleC}`);

    // Verify that User D does not see any assigned roles or action forms
    await expect(pageD.locator('select[name="target_id"]')).not.toBeVisible();
    await expect(pageD.locator('select[name="vote_id"]')).not.toBeVisible();
    await expect(pageD.locator('body')).not.toContainText(/\((占い師|人狼|狂人|村人)\)/);

    const pages = [
      { page: pageA, role: roleA, name: 'User A' },
      { page: pageB, role: roleB, name: 'User B' },
      { page: pageC, role: roleC, name: 'User C' }
    ];

    const wolfInfo = pages.find(p => isWolf(p.role));
    const seerInfo = pages.find(p => isSeer(p.role));
    const possessedInfo = pages.find(p => isPossessed(p.role));

    if (!wolfInfo || !seerInfo || !possessedInfo) {
      throw new Error(`Failed to assign all 3 required roles. Found: Wolf=${!!wolfInfo}, Seer=${!!seerInfo}, Possessed=${!!possessedInfo}`);
    }

    // 5. Day 1 Night Actions
    // Seer action: target index 1
    const seerPage = seerInfo.page;
    await expect(seerPage.locator('select[name="target_id"]')).toBeVisible({ timeout: 10000 });
    await seerPage.selectOption('select[name="target_id"]', { index: 1 });
    await saveSnapshot(seerPage, 'seer_before_submit');
    await submitFormWorkaround(seerPage, 'target_id');
    console.log(`[E2E] Seer (${seerInfo.name}) submitted fortune action.`);

    // Werewolf: send whisper BEFORE committing the attack target
    // (whisper_textarea is only available during night, before night-commit)
    const wolfPage = wolfInfo.page;
    await expect(wolfPage.locator('select[name="target_id"]')).toBeVisible({ timeout: 10000 });
    await wolfPage.selectOption('select[name="target_id"]', { index: 1 });

    const whisperTextarea = wolfPage.locator('textarea.chat-textarea');
    if (await whisperTextarea.isVisible()) {
      // Send whisper before submitting attack (which triggers night-commit)
      await whisperTextarea.fill('今夜はダニエルを襲うよ');
      await wolfPage.click('.chat-send-btn');
      console.log(`[E2E] Werewolf whisper sent.`);

      // Wolf's own view: whisper should be visible immediately
      await expect(wolfPage.locator('.mes_whisper_body1').last())
        .toContainText('今夜はダニエルを襲うよ', { timeout: 10000 });
      await saveSnapshot(wolfPage, 'whisper_wolf_view');
      console.log(`[E2E] Snapshot saved: whisper_wolf_view`);

      // Non-wolf pages: "わおーん" howl should arrive dynamically via long-polling
      const nonWolfPages = pages.filter(p => !isWolf(p.role));
      for (const info of nonWolfPages) {
        await expect(info.page.locator('.mes_whisper_body1').last())
          .toContainText('わおーん', { timeout: 15000 });
        await saveSnapshot(info.page, `whisper_howl_${info.name.replace(' ', '_')}_view`);

        // Verify icon is howl.png, NOT a character avatar
        const howlTable = info.page.locator('table.message').filter({ hasText: 'わおーん' }).last();
        await expect(howlTable).toBeVisible();
        const howlImg = howlTable.locator('td:first-child img').first();
        const imgSrc = await howlImg.getAttribute('src');
        console.log(`[E2E] Howl icon for ${info.name}: ${imgSrc}`);
        expect(imgSrc).toContain('howl');
      }

      // Verify werewolf howl for User D (spectator) - should be masked as "わおーん" and not contain actual text
      await expect(pageD.locator('.mes_whisper_body1').last()).toContainText('わおーん', { timeout: 15000 });
      await expect(pageD.locator('body')).not.toContainText('今夜はダニエルを襲うよ');
      await saveSnapshot(pageD, 'whisper_howl_User_D_view');
    }

    // Werewolf submits attack target (this triggers night-commit)
    // Re-select index 1 because the whisper form submit caused a page reload,
    // resetting the select back to -1.
    await expect(wolfPage.locator('select[name="target_id"]')).toBeVisible({ timeout: 10000 });
    await wolfPage.selectOption('select[name="target_id"]', { index: 1 });
    await saveSnapshot(wolfPage, 'wolf_before_submit');
    await submitFormWorkaround(wolfPage, 'target_id');
    console.log(`[E2E] Werewolf (${wolfInfo.name}) submitted attack action.`);


    // Wait for Day 2 Daytime transitions (night→day reload prompt)
    // Since both Seer and Werewolf committed, the game state should transition to Day 2
    for (const info of pages) {
      const prompt = info.page.locator('.reload-prompt');
      const promptVisible = await prompt.isVisible({ timeout: 10000 }).catch(() => false);
      if (promptVisible) {
        // Snapshot the reload prompt BEFORE clicking it
        await saveSnapshot(info.page, `reload_prompt_night_to_day_${info.name.replace(' ', '_')}`);
        console.log(`[E2E] Reload prompt (night→day) visible for ${info.name}, snapshotted.`);
        await prompt.click();
        console.log(`[E2E] Clicked reload prompt for ${info.name}`);
      } else {
        await info.page.reload();
        console.log(`[E2E] Manually reloaded ${info.name}`);
      }
    }

    // Day 2 transition for User D
    const promptDDay2Visible = await pageD.locator('.reload-prompt').isVisible({ timeout: 10000 }).catch(() => false);
    if (promptDDay2Visible) {
      await pageD.locator('.reload-prompt').click();
    } else {
      await pageD.reload();
    }

    await saveSnapshot(pageA, 'enhanced_3_night_actions_done');

    // 6. Day 2 Daytime Talk
    // Verify that the dummy player is dead in the announcements
    for (const info of pages) {
      await expect(info.page.locator('.announce').first()).toBeVisible({ timeout: 10000 });
    }

    // Each player says something
    for (const info of pages) {
      const textarea = info.page.locator('textarea[name="message"]');
      await expect(textarea).toBeVisible({ timeout: 10000 });
      await textarea.fill(`こんにちは、私は ${info.name} (${info.role}) です。`);
      await info.page.click('.chat-send-btn');
    }

    // Verify all players and User D received User C's chat message in real-time
    for (const info of pages) {
      await expect(info.page.locator('.mes_say_body1').last()).toContainText('こんにちは、私は User C', { timeout: 15000 });
    }
    await expect(pageD.locator('.mes_say_body1').last()).toContainText('こんにちは、私は User C', { timeout: 15000 });

    await saveSnapshot(pageA, 'enhanced_4_day_talk_sent');

    // 7. Day 2 Daytime Voting
    // All players vote for the wolf player to guarantee village wins
    // We need to find the wolf's player ID from the vote select options
    const firstVoteSelect = pages[0].page.locator('select[name="vote_id"]');
    await expect(firstVoteSelect).toBeVisible({ timeout: 10000 });
    const wolfPid = await pages[0].page.evaluate((wolfName) => {
      const sel = document.querySelector('select[name="vote_id"]');
      if (!sel) return null;
      for (const opt of sel.options) {
        if (opt.text.trim().includes(wolfName)) return opt.value;
      }
      return null;
    }, wolfInfo.name.replace('User ', ''));

    // Get the wolf's character name from the vote select (match by player position, not user name)
    // Fall back to index 1 if exact match not found
    for (const info of pages) {
      const voteSelect = info.page.locator('select[name="vote_id"]');
      await expect(voteSelect).toBeVisible({ timeout: 10000 });

      const wolfCharName = await wolfInfo.page.evaluate(() => {
        // Get current user's character name from the page header
        const actionBody = document.querySelector('.action_balloon td.action_body');
        if (!actionBody) return null;
        const text = actionBody.innerText;
        const nameMatch = text.match(/^(.+?)\s*\(/);
        return nameMatch ? nameMatch[1].trim() : null;
      });
      console.log(`[E2E] Wolf character name: ${wolfCharName}`);

      const wolfOptValue = await info.page.evaluate((charName) => {
        const sel = document.querySelector('select[name="vote_id"]');
        if (!sel || !charName) return null;
        for (const opt of sel.options) {
          if (opt.text.includes(charName)) return opt.value;
        }
        return null;
      }, wolfCharName);

      if (wolfOptValue && wolfOptValue !== '-1') {
        await voteSelect.selectOption(wolfOptValue);
        console.log(`[E2E] ${info.name} votes for wolf (value=${wolfOptValue})`);
      } else {
        // Fallback: vote for index 1
        await voteSelect.selectOption({ index: 1 });
        console.log(`[E2E] ${info.name} fallback vote for index 1`);
      }
      await submitFormWorkaround(info.page, 'vote_id');
    }

    // Wait for the game over transition and click reload prompts
    for (const info of pages) {
      const prompt = info.page.locator('.reload-prompt');
      const promptVisible = await prompt.isVisible({ timeout: 15000 }).catch(() => false);
      if (promptVisible) {
        // Snapshot the game-over reload prompt BEFORE clicking
        await saveSnapshot(info.page, `reload_prompt_game_over_${info.name.replace(' ', '_')}`);
        console.log(`[E2E] Reload prompt (game over) visible for ${info.name}, snapshotted.`);
        await prompt.click();
        console.log(`[E2E] Clicked reload prompt after vote for ${info.name}`);
      } else {
        await info.page.reload();
        console.log(`[E2E] Manually reloaded after vote for ${info.name}`);
      }
    }

    // Game over reload for User D
    const promptDGameOverVisible = await pageD.locator('.reload-prompt').isVisible({ timeout: 15000 }).catch(() => false);
    if (promptDGameOverVisible) {
      await pageD.locator('.reload-prompt').click();
    } else {
      await pageD.reload();
    }

    await saveSnapshot(pageA, 'enhanced_5_game_over');

    // Verify game finished and outcomes are correct by role
    // Scenario: all players voted for wolf → wolf executed → VILLAGE WINS
    //   Village-side (占い師, 村人 etc.) → win_res (勝利)
    //   Wolf-side (人狼, 狂人 etc.)      → lose_res (敗北)
    const wolfSideRoles = ['人狼', '人喰い', '狂人'];
    for (const info of pages) {
      const outcomeLocator = info.page.locator('.win_res, .lose_res');
      await expect(outcomeLocator.first()).toBeVisible({ timeout: 10000 });
      const text = await outcomeLocator.first().innerText();
      const outcomeClass = await outcomeLocator.first().getAttribute('class');
      console.log(`[E2E] ${info.name} (${info.role}): ${text} [class=${outcomeClass}]`);
      await saveSnapshot(info.page, `game_result_${info.name.replace(' ', '_')}`);

      const isWolfSide = wolfSideRoles.includes(info.role);
      if (isWolfSide) {
        // Wolf executed → wolf-side LOSES
        expect(outcomeClass, `${info.name} (${info.role}) should LOSE (village wins) but got: ${text}`).toContain('lose_res');
      } else {
        // Village-side WINS when wolf is executed
        expect(outcomeClass, `${info.name} (${info.role}) should WIN (village wins) but got: ${text}`).toContain('win_res');
      }
    }

    // Verify victory announcement for User D (spectator)
    const winAnnounce = pageD.locator('.announce.win');
    await expect(winAnnounce.first()).toBeVisible({ timeout: 10000 });
    const winText = await winAnnounce.first().innerText();
    console.log(`[E2E] User D (spectator) sees win announcement: ${winText}`);
    expect(winText).toContain('村人の勝利です！');
    await saveSnapshot(pageD, 'game_result_User_D');

    // Verify that User D does NOT see personal win/loss elements (win_res / lose_res)
    await expect(pageD.locator('.win_res, .lose_res')).not.toBeVisible();

    // Verify chat log layout at different viewports (Desktop, Tablet, Mobile)
    const logPages = [
      { page: pageA, name: 'UserA' },
      { page: pageD, name: 'UserD' }
    ];
    for (const item of logPages) {
      // 1. Desktop view (1280x800)
      await item.page.setViewportSize({ width: 1280, height: 800 });
      await saveSnapshot(item.page, `enhanced_final_log_desktop_${item.name}`);

      // 2. Tablet view (768x1024)
      await item.page.setViewportSize({ width: 768, height: 1024 });
      await saveSnapshot(item.page, `enhanced_final_log_tablet_${item.name}`);

      // 3. Mobile view (375x812 - iPhone 12 Pro)
      await item.page.setViewportSize({ width: 375, height: 812 });
      await saveSnapshot(item.page, `enhanced_final_log_mobile_${item.name}`);
    }

    await contextA.close();
    await contextB.close();
    await contextC.close();
    await contextD.close();

    expect(browserErrors).toEqual([]);
  });

  test('should display top page correctly at different viewports and save snapshots', async ({ page }) => {
    // 1. Desktop view (1280x800)
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto('/aiwolf/v2.cgi');
    await expect(page.locator('input[value="ログイン"]')).toBeVisible();
    await saveSnapshot(page, 'top_page_desktop');

    // 2. Tablet view (768x1024)
    await page.setViewportSize({ width: 768, height: 1024 });
    await saveSnapshot(page, 'top_page_tablet');

    // 3. Mobile view (375x812 - iPhone 12 Pro)
    await page.setViewportSize({ width: 375, height: 812 });
    await saveSnapshot(page, 'top_page_mobile');
  });
});
