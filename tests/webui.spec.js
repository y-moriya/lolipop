const { test, expect } = require('@playwright/test');

test.describe('anman-ai WebUI E2E Tests', () => {
  test('should alert on tab switch with unsaved changes, cancel switch, accept switch, and auto-save on connection test', async ({ page }) => {
    // Collect console logs and errors from browser
    const browserErrors = [];
    page.on('console', msg => {
      if (msg.type() === 'error') {
        console.error(`[BROWSER ERROR] ${msg.text()}`);
        browserErrors.push(msg.text());
      } else {
        console.log(`[BROWSER LOG] ${msg.text()}`);
      }
    });
    page.on('pageerror', exception => {
      console.error(`[BROWSER EXCEPTION] ${exception.stack || exception.message}`);
      browserErrors.push(exception.message);
    });

    // 1. Open WebUI (running at port 8064)
    await page.goto('http://localhost:8064');
    
    // Check if dashboard tab is loaded and visible
    const tabDashboard = page.locator('#tab-dashboard');
    await expect(tabDashboard).toBeVisible();

    const tabSettings = page.locator('#tab-settings');
    await expect(tabSettings).toBeVisible();

    // 2. Go to Settings tab
    await tabSettings.click();
    await page.waitForTimeout(500); // Allow config to load

    // Read the original server url value
    const originalServerUrl = await page.locator('#server-url').inputValue();
    console.log(`Original server URL: ${originalServerUrl}`);

    // Fill in required fields that might be empty (to pass HTML5 validation)
    await page.fill('#user-userid', 'test_user');
    await page.fill('#user-password', 'test_password');
    // Save these fields first so we establish a clean baseline
    await page.locator('#btn-save-settings').click();
    await page.waitForTimeout(500);

    // 3. Make a change in the form
    const changedUrl = 'http://localhost:8063/changed_url_for_test';
    await page.fill('#server-url', changedUrl);

    // 4. Try to switch back to Dashboard - should trigger alert and we CANCEL it
    let dialogMessage = '';
    const handleDismiss = async dialog => {
      dialogMessage = dialog.message();
      console.log(`Dialog message received (dismissing): ${dialogMessage}`);
      await dialog.dismiss();
    };
    
    page.once('dialog', handleDismiss);
    await tabDashboard.click();

    // Verify dialog was shown and contains expected message
    expect(dialogMessage).toContain('設定の変更が保存されていません');

    // Verify we are still on the settings tab
    const viewSettings = page.locator('#view-settings');
    await expect(viewSettings).toHaveClass(/active/);
    
    // Value should still be the changed one
    const serverUrlAfterCancel = await page.locator('#server-url').inputValue();
    expect(serverUrlAfterCancel).toBe(changedUrl);

    // 5. Try to switch back to Dashboard again - this time we ACCEPT it
    const handleAccept = async dialog => {
      dialogMessage = dialog.message();
      console.log(`Dialog message received (accepting): ${dialogMessage}`);
      await dialog.accept();
    };

    page.once('dialog', handleAccept);
    await tabDashboard.click();

    // Verify dialog was shown
    expect(dialogMessage).toContain('設定の変更が保存されていません');

    // Verify we successfully switched to the dashboard view
    const viewDashboard = page.locator('#view-dashboard');
    await expect(viewDashboard).toHaveClass(/active/);

    // 6. Go back to Settings and verify original config was re-loaded (since we didn't save)
    await tabSettings.click();
    await page.waitForTimeout(500); // Allow config to load
    const serverUrlAfterReload = await page.locator('#server-url').inputValue();
    // Since we reloaded settings, the changed url should have been lost
    // Note: original user/password we filled at step 2 was saved, but changedUrl was not.
    expect(serverUrlAfterReload).not.toBe(changedUrl);

    // 7. Make a change again and run connection test (which should auto-save)
    const testUrl = 'http://localhost:8063/aiwolf'; // Using normal URL so CGI test actually runs or fails gracefully
    await page.fill('#server-url', testUrl);

    // Wait 500ms to let all input/change events settle and blur the input
    await page.locator('#server-url').blur();
    await page.waitForTimeout(500);

    // Click "CGI接続テスト"
    const btnTestAiwolf = page.locator('#btn-test-aiwolf');
    await btnTestAiwolf.click();

    // Wait for the test to complete (it should show test result in status element)
    const aiwolfTestStatus = page.locator('#aiwolf-test-status');
    await expect(aiwolfTestStatus).not.toContainText('設定を保存中...', { timeout: 10000 });
    await expect(aiwolfTestStatus).not.toContainText('接続テスト中...', { timeout: 10000 });
    
    // Print out the statuses for diagnostic purposes
    const saveStatus = await page.locator('#save-status-msg').textContent();
    const testStatus = await aiwolfTestStatus.textContent();
    console.log(`Diagnostic - Save Status Msg: "${saveStatus}"`);
    console.log(`Diagnostic - Test Status Msg: "${testStatus}"`);

    // 8. Try to switch to Dashboard - should NOT trigger alert because it auto-saved
    let dialogTriggered = false;
    let fallbackDialogMessage = '';
    const handleUnexpectedDialog = async dialog => {
      dialogTriggered = true;
      fallbackDialogMessage = dialog.message();
      console.log(`[WARNING] Unexpected dialog triggered: ${fallbackDialogMessage}`);
      await dialog.accept(); // Accept it so the browser doesn't hang
    };
    page.on('dialog', handleUnexpectedDialog);

    await tabDashboard.click();
    await page.waitForTimeout(500); // Wait briefly to see if dialog pops up

    // Clean up event listener
    page.off('dialog', handleUnexpectedDialog);

    expect(dialogTriggered).toBe(false);
    await expect(viewDashboard).toHaveClass(/active/);

    // 9. Go back to Settings and verify that the auto-saved change actually persisted
    await tabSettings.click();
    await page.waitForTimeout(500);
    const finalServerUrl = await page.locator('#server-url').inputValue();
    expect(finalServerUrl).toBe(testUrl);

    // 10. Restore the original values (including user/password) so we don't mess up user's default configuration
    await page.fill('#server-url', originalServerUrl);
    await page.fill('#user-userid', '');
    await page.fill('#user-password', '');
    await page.locator('#btn-save-settings').click();
    await page.waitForTimeout(500);
  });
});
