// Types & interfaces
interface Player {
  userid: string;
  num_id: number;
  dead: number;
  role: string;
}

interface ChatLog {
  id: string;
  day: string;
  time: string;
  type: string;
  type_code: string;
  speaker: string;
  content: string;
  is_mine?: boolean;
}

interface GameState {
  current_day: number;
  is_night: boolean;
  my_name: string;
  my_role: string;
  my_reasoning_notes: string;
  players: Record<string, Player>;
  chat_logs: ChatLog[];
  action_results: string[];
  werewolf_partners: string[];
  game_started: boolean;
  summary: string;
}

interface ClientStatus {
  running: boolean;
  version: string;
  my_name: string;
  my_role: string;
  vid: number;
  url: string;
  game_started: boolean;
}

// App State
let currentTab = 'dashboard';
let isClientRunning = false;
let statusIntervalId: number | null = null;
let gameIntervalId: number | null = null;
let logsIntervalId: number | null = null;
let lastChatLogsCount = 0;

// DOM Elements
const elements = {
  tabDashboard: document.getElementById('tab-dashboard') as HTMLButtonElement,
  tabSettings: document.getElementById('tab-settings') as HTMLButtonElement,
  tabLogs: document.getElementById('tab-logs') as HTMLButtonElement,
  
  viewDashboard: document.getElementById('view-dashboard') as HTMLElement,
  viewSettings: document.getElementById('view-settings') as HTMLElement,
  viewLogs: document.getElementById('view-logs') as HTMLElement,
  
  pageTitle: document.getElementById('page-title') as HTMLElement,
  appVersion: document.getElementById('app-version') as HTMLElement,
  
  statusDot: document.getElementById('status-dot') as HTMLElement,
  statusText: document.getElementById('status-text') as HTMLElement,
  btnToggleClient: document.getElementById('btn-toggle-client') as HTMLButtonElement,
  
  // Dashboard Info Elements
  infoUsername: document.getElementById('info-username') as HTMLElement,
  infoRole: document.getElementById('info-role') as HTMLElement,
  infoVid: document.getElementById('info-vid') as HTMLElement,
  infoDay: document.getElementById('info-day') as HTMLElement,
  
  playersList: document.getElementById('players-list') as HTMLElement,
  actionResults: document.getElementById('action-results') as HTMLElement,
  chatLogs: document.getElementById('chat-logs') as HTMLElement,
  
  // Settings Form
  settingsForm: document.getElementById('settings-form') as HTMLFormElement,
  fallbackEnable: document.getElementById('fallback-enable') as HTMLInputElement,
  fallbackWrapper: document.getElementById('fallback-settings-wrapper') as HTMLElement,
  btnSaveSettings: document.getElementById('btn-save-settings') as HTMLButtonElement,
  saveStatusMsg: document.getElementById('save-status-msg') as HTMLElement,
  
  // Logs Panel
  logOutput: document.getElementById('log-output') as HTMLElement,
  logLinesCount: document.getElementById('log-lines-count') as HTMLSelectElement,
  btnClearLogView: document.getElementById('btn-clear-log-view') as HTMLButtonElement,
};

// Initialize Tab Switching
function initTabs() {
  const switchTab = (tabName: string) => {
    currentTab = tabName;
    
    // Tab active states
    elements.tabDashboard.classList.toggle('active', tabName === 'dashboard');
    elements.tabSettings.classList.toggle('active', tabName === 'settings');
    elements.tabLogs.classList.toggle('active', tabName === 'logs');
    
    // Views active states
    elements.viewDashboard.classList.toggle('active', tabName === 'dashboard');
    elements.viewSettings.classList.toggle('active', tabName === 'settings');
    elements.viewLogs.classList.toggle('active', tabName === 'logs');
    
    // Header page title
    elements.pageTitle.textContent = 
      tabName === 'dashboard' ? 'ダッシュボード' :
      tabName === 'settings' ? '設定画面' : 'システムログ';

    // Start/Stop view-specific polling loops
    stopAllPolling();
    startAllPolling();

    if (tabName === 'settings') {
      loadConfig();
    }
  };

  elements.tabDashboard.addEventListener('click', () => switchTab('dashboard'));
  elements.tabSettings.addEventListener('click', () => switchTab('settings'));
  elements.tabLogs.addEventListener('click', () => switchTab('logs'));
}

// Stop polling for tab sections
function stopAllPolling() {
  if (gameIntervalId) { clearInterval(gameIntervalId); gameIntervalId = null; }
  if (logsIntervalId) { clearInterval(logsIntervalId); logsIntervalId = null; }
}

// Start polling depending on currently active tab
function startAllPolling() {
  // Always poll status regardless of tab
  if (!statusIntervalId) {
    pollStatus();
    statusIntervalId = window.setInterval(pollStatus, 2000);
  }

  if (currentTab === 'dashboard') {
    pollGameState();
    gameIntervalId = window.setInterval(pollGameState, 3000);
  } else if (currentTab === 'logs') {
    pollLogs();
    logsIntervalId = window.setInterval(pollLogs, 1500);
  }
}

// 1. Status Polling API
async function pollStatus() {
  try {
    const res = await fetch('/api/status');
    if (!res.ok) throw new Error('Failed to fetch status');
    const status: ClientStatus = await res.json();
    
    isClientRunning = status.running;
    elements.appVersion.textContent = status.version;
    
    // Apply UI state
    if (isClientRunning) {
      elements.statusDot.className = 'status-dot online';
      elements.statusText.textContent = '稼働中';
      elements.btnToggleClient.textContent = '停止する';
      elements.btnToggleClient.className = 'btn btn-danger btn-start';
    } else {
      elements.statusDot.className = 'status-dot offline';
      elements.statusText.textContent = '停止中';
      elements.btnToggleClient.textContent = '起動する';
      elements.btnToggleClient.className = 'btn btn-primary btn-start';
    }
  } catch (error) {
    console.error('Error polling status:', error);
    elements.statusDot.className = 'status-dot offline';
    elements.statusText.textContent = '接続エラー';
  }
}

// Start / Stop client loops
async function toggleClient() {
  elements.btnToggleClient.disabled = true;
  const endpoint = isClientRunning ? '/api/stop' : '/api/start';
  
  try {
    const res = await fetch(endpoint, { method: 'POST' });
    if (!res.ok) throw new Error('API action failed');
    await pollStatus();
  } catch (error) {
    alert(`操作に失敗しました: ${error}`);
  } finally {
    elements.btnToggleClient.disabled = false;
  }
}

// 2. Game State Polling API
async function pollGameState() {
  try {
    const res = await fetch('/api/game_state');
    if (!res.ok) throw new Error('Failed to fetch game state');
    const state: GameState = await res.json();

    // Map upper info card values
    elements.infoUsername.textContent = state.my_name || '-';
    elements.infoRole.textContent = state.my_role || '不明';
    
    const isNightText = state.is_night ? ' (夜)' : ' (昼)';
    elements.infoDay.textContent = state.game_started 
      ? `${state.current_day}日目${isNightText}` 
      : '開始待ち';
    
    // Check if vid is active or not
    const resStatus = await fetch('/api/status');
    const status: ClientStatus = await resStatus.json();
    elements.infoVid.textContent = status.vid > 0 ? status.vid.toString() : '自動エントリー監視中';

    // Populate players list
    updatePlayersList(state.players, state.my_name);

    // Action results
    updateActionResults(state.action_results);

    // Chat Logs
    updateChatLogs(state.chat_logs);

  } catch (error) {
    // If not started yet, show empty/waiting
    console.warn('Game state not ready:', error);
  }
}

function updatePlayersList(players: Record<string, Player>, myName: string) {
  if (!players || Object.keys(players).length === 0) {
    elements.playersList.innerHTML = '<div class="empty-state">ゲーム開始を待っています...</div>';
    return;
  }

  let html = '';
  Object.entries(players)
    .sort((a, b) => a[1].num_id - b[1].num_id)
    .forEach(([name, p]) => {
      const isMe = name === myName;
      const isDead = p.dead !== 0;
      
      html += `
        <div class="player-item ${isMe ? 'me' : ''} ${isDead ? 'is-dead' : ''}">
          <div class="player-name">${isMe ? '⭐ ' : ''}${name}</div>
          <div class="player-role">${p.role !== '不明' ? p.role : ''}</div>
          <span class="player-status-badge ${isDead ? 'dead' : 'alive'}">
            ${isDead ? '無残な死' : '生存'}
          </span>
        </div>
      `;
    });

  elements.playersList.innerHTML = html;
}

function updateActionResults(actions: string[]) {
  if (!actions || actions.length === 0) {
    elements.actionResults.innerHTML = '<div class="empty-state">履歴はありません。</div>';
    return;
  }

  let html = '';
  actions.forEach(action => {
    html += `<div class="action-item">${escapeHTML(action)}</div>`;
  });
  elements.actionResults.innerHTML = html;
}

function updateChatLogs(logs: ChatLog[]) {
  if (!logs || logs.length === 0) {
    elements.chatLogs.innerHTML = '<div class="empty-state">ログはありません。</div>';
    return;
  }

  let html = '';
  logs.forEach(log => {
    const timePart = log.time ? `<span class="msg-time">${log.time}</span>` : '';
    let msgClass = log.type_code || '';
    if (log.type === 'system') msgClass = 'system';
    if (log.type === 'state_change') msgClass = 'state_change';
    if (log.is_mine) msgClass += ' mine';

    // Format content and clean up
    let displayContent = log.content;
    const speakerText = log.speaker ? `<span class="msg-speaker">${escapeHTML(log.speaker)}</span>` : '';

    html += `
      <div class="chat-msg ${msgClass}">
        ${timePart}
        <div>${speakerText}${escapeHTML(displayContent)}</div>
      </div>
    `;
  });

  elements.chatLogs.innerHTML = html;

  // Scroll to bottom if we got new logs
  if (logs.length > lastChatLogsCount) {
    elements.chatLogs.scrollTop = elements.chatLogs.scrollHeight;
    lastChatLogsCount = logs.length;
  }
}

// 3. Settings Load & Save APIs
async function loadConfig() {
  try {
    const res = await fetch('/api/config');
    if (!res.ok) throw new Error('Failed to load configuration');
    const config = await res.json();

    setFormData(elements.settingsForm, config);
    
    // Update fallback toggle and field states
    const hasFallback = !!config.llm_fallback;
    elements.fallbackEnable.checked = hasFallback;
    elements.fallbackWrapper.classList.toggle('disabled', !hasFallback);
  } catch (error) {
    alert(`設定のロードに失敗しました: ${error}`);
  }
}

async function saveConfig() {
  elements.btnSaveSettings.disabled = true;
  elements.saveStatusMsg.textContent = '保存中...';
  elements.saveStatusMsg.className = 'save-status-msg';

  try {
    const data = getFormData(elements.settingsForm);
    
    // If fallback is not enabled, strip it from POST
    if (!elements.fallbackEnable.checked) {
      delete data.llm_fallback;
    }

    const res = await fetch('/api/config', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });

    if (!res.ok) {
      const err = await res.json();
      throw new Error(err.error || 'Server rejected changes');
    }

    elements.saveStatusMsg.textContent = '✅ 設定を保存し、適用しました！';
    elements.saveStatusMsg.className = 'save-status-msg success';
  } catch (error: any) {
    elements.saveStatusMsg.textContent = `❌ 保存失敗: ${error.message}`;
    elements.saveStatusMsg.className = 'save-status-msg error';
  } finally {
    elements.btnSaveSettings.disabled = false;
    setTimeout(() => {
      elements.saveStatusMsg.textContent = '';
    }, 4000);
  }
}

// Form helper: Gather nested object structure from form names (e.g. server.url => {server: {url: ...}})
function getFormData(form: HTMLFormElement): any {
  const formData = new FormData(form);
  const data: any = {};
  
  formData.forEach((value, key) => {
    const keys = key.split('.');
    let current = data;
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i];
      if (i === keys.length - 1) {
        // Value type resolution
        if (value === 'true') {
          current[k] = true;
        } else if (value === 'false') {
          current[k] = false;
        } else if (!isNaN(Number(value)) && value.toString().trim() !== '') {
          current[k] = Number(value);
        } else {
          current[k] = value;
        }
      } else {
        current[k] = current[k] || {};
        current = current[k];
      }
    }
  });

  // Handle checkboxes
  form.querySelectorAll('input[type="checkbox"]').forEach((el: any) => {
    const key = el.name;
    if (!key) return;
    const keys = key.split('.');
    let current = data;
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i];
      if (i === keys.length - 1) {
        current[k] = el.checked;
      } else {
        current[k] = current[k] || {};
        current = current[k];
      }
    }
  });

  return data;
}

// Form helper: Set nested object values to inputs
function setFormData(form: HTMLFormElement, data: any) {
  form.querySelectorAll('input, select').forEach((el: any) => {
    const key = el.name;
    if (!key) return;
    const keys = key.split('.');
    let value = data;
    for (const k of keys) {
      if (value === undefined || value === null) {
        value = undefined;
        break;
      }
      value = value[k];
    }
    
    if (value !== undefined) {
      if (el.type === 'checkbox') {
        el.checked = !!value;
      } else {
        el.value = value;
      }
    }
  });
}

// 4. System Logs API
async function pollLogs() {
  try {
    const lines = elements.logLinesCount.value;
    const res = await fetch(`/api/logs?lines=${lines}`);
    if (!res.ok) throw new Error('Failed to fetch logs');
    const data = await res.json();

    if (data.success && data.logs) {
      const container = elements.logOutput;
      
      let html = '';
      data.logs.forEach((line: string) => {
        let levelClass = '';
        if (line.includes('[ERROR]') || line.includes('[Fatal Error]') || line.includes('Error')) {
          levelClass = 'error';
        } else if (line.includes('[WARNING]') || line.includes('WARN')) {
          levelClass = 'WARN';
        } else if (line.includes('[INFO]') || line.includes('[System]')) {
          levelClass = 'system';
        }
        html += `<div class="log-line ${levelClass}">${escapeHTML(line)}</div>`;
      });

      container.innerHTML = html;
      
      // Auto scroll to bottom
      container.scrollTop = container.scrollHeight;
    }
  } catch (error) {
    console.error('Error fetching logs:', error);
  }
}

// Helper: escape HTML tags
function escapeHTML(str: string): string {
  if (!str) return '';
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

// Setup Event Listeners
function setupListeners() {
  elements.btnToggleClient.addEventListener('click', toggleClient);
  
  // Settings Form Submit
  elements.btnSaveSettings.addEventListener('click', (e) => {
    e.preventDefault();
    if (elements.settingsForm.checkValidity()) {
      saveConfig();
    } else {
      elements.settingsForm.reportValidity();
    }
  });

  // Fallback Enable Toggle
  elements.fallbackEnable.addEventListener('change', () => {
    const checked = elements.fallbackEnable.checked;
    elements.fallbackWrapper.classList.toggle('disabled', !checked);
    
    // Set fallback inputs as required/not-required dynamically
    elements.fallbackWrapper.querySelectorAll('input').forEach(input => {
      if (input.name === 'llm_fallback.model') {
        input.required = checked;
      }
    });
  });

  // Logs lines count change
  elements.logLinesCount.addEventListener('change', () => {
    pollLogs();
  });

  // Clear log screen
  elements.btnClearLogView.addEventListener('click', () => {
    elements.logOutput.innerHTML = '<div class="log-line system">ログ画面がクリアされました。待機中...</div>';
  });
}

// Application Entrance
function main() {
  initTabs();
  setupListeners();
  startAllPolling();
}

window.addEventListener('DOMContentLoaded', main);
