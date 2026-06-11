// ============================================================
// Dynamics 365 Text Resizer — Popup Script
// ============================================================

document.getElementById('versionDisplay').textContent =
  'v' + chrome.runtime.getManifest().version;

const DEFAULTS = {
  enabled: true,
  autoFit: true,
  minHeight: 180,
  showHighlight: true,
  customFields: []
};

const enabledToggle = document.getElementById('enabledToggle');
const autoFitCheck = document.getElementById('autoFit');
const minHeightSlider = document.getElementById('minHeight');
const showHighlightCheck = document.getElementById('showHighlight');
const heightVal = document.getElementById('heightVal');
const statusDot = document.getElementById('statusDot');
const statusText = document.getElementById('statusText');
const resetBtn = document.getElementById('resetBtn');
const targetsToggle = document.getElementById('targetsToggle');
const targetsArrow = document.getElementById('targetsArrow');
const targetsList = document.getElementById('targetsList');
const customFieldInput = document.getElementById('customFieldInput');
const addFieldBtn = document.getElementById('addFieldBtn');
const customFieldsList = document.getElementById('customFieldsList');
const customEmpty = document.getElementById('customEmpty');

let customFields = [];

// Load saved settings
chrome.storage.sync.get(DEFAULTS, (settings) => {
  enabledToggle.checked = settings.enabled;
  autoFitCheck.checked = settings.autoFit;
  minHeightSlider.value = settings.minHeight;
  showHighlightCheck.checked = settings.showHighlight;
  heightVal.textContent = settings.minHeight + 'px';
  customFields = settings.customFields || [];
  renderCustomFields();
  updateStatus(settings.enabled);
});

function updateStatus(enabled) {
  statusDot.classList.toggle('off', !enabled);
  statusText.textContent = enabled ? 'Active' : 'Disabled';
}

function saveSettings() {
  const settings = {
    enabled: enabledToggle.checked,
    autoFit: autoFitCheck.checked,
    minHeight: parseInt(minHeightSlider.value, 10),
    showHighlight: showHighlightCheck.checked,
    customFields: customFields
  };

  chrome.storage.sync.set(settings);
  updateStatus(settings.enabled);

  // Notify all matching Dynamics tabs
  const patterns = [
    'https://*.crm.dynamics.com/*',
    'https://*.crm2.dynamics.com/*',
    'https://*.crm3.dynamics.com/*',
    'https://*.crm4.dynamics.com/*',
    'https://*.crm5.dynamics.com/*',
    'https://*.crm6.dynamics.com/*',
    'https://*.crm7.dynamics.com/*',
    'https://*.crm8.dynamics.com/*',
    'https://*.crm9.dynamics.com/*',
    'https://*.crm11.dynamics.com/*',
    'https://*.crm12.dynamics.com/*',
    'https://*.crm13.dynamics.com/*',
    'https://*.crm14.dynamics.com/*',
    'https://*.crm15.dynamics.com/*',
    'https://*.crm16.dynamics.com/*',
    'https://*.crm17.dynamics.com/*',
    'https://*.microsoftdynamics.us/*',
    'https://*.microsoftdynamics.de/*'
  ];

  patterns.forEach(url => {
    chrome.tabs.query({ url }, (tabs) => {
      tabs.forEach(tab => {
        chrome.tabs.sendMessage(tab.id, {
          type: 'settingsUpdated',
          settings
        }).catch(() => {});
      });
    });
  });
}

// Render the custom fields list
function renderCustomFields() {
  customFieldsList.innerHTML = '';
  customEmpty.style.display = customFields.length === 0 ? 'block' : 'none';

  customFields.forEach((field, index) => {
    const li = document.createElement('li');

    const span = document.createElement('span');
    span.textContent = field;
    li.appendChild(span);

    const btn = document.createElement('button');
    btn.classList.add('remove-btn');
    btn.textContent = '×'; // × character
    btn.title = 'Remove';
    btn.addEventListener('click', () => {
      customFields.splice(index, 1);
      renderCustomFields();
      saveSettings();
    });
    li.appendChild(btn);

    customFieldsList.appendChild(li);
  });
}

// Add field button — enable/disable based on input
customFieldInput.addEventListener('input', () => {
  addFieldBtn.disabled = customFieldInput.value.trim() === '';
});

// Submit on Enter key
customFieldInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && customFieldInput.value.trim() !== '') {
    addCustomField();
  }
});

addFieldBtn.addEventListener('click', addCustomField);

function addCustomField() {
  const value = customFieldInput.value.trim();
  if (!value) return;

  // Prevent duplicates (case-sensitive, matching aria-label exactly)
  if (customFields.includes(value)) {
    customFieldInput.value = '';
    addFieldBtn.disabled = true;
    return;
  }

  customFields.push(value);
  customFieldInput.value = '';
  addFieldBtn.disabled = true;
  renderCustomFields();
  saveSettings();
  customFieldInput.focus();
}

// Event listeners for other controls
enabledToggle.addEventListener('change', saveSettings);
autoFitCheck.addEventListener('change', saveSettings);
showHighlightCheck.addEventListener('change', saveSettings);

minHeightSlider.addEventListener('input', () => {
  heightVal.textContent = minHeightSlider.value + 'px';
});
minHeightSlider.addEventListener('change', saveSettings);

// Reset clears custom fields too
resetBtn.addEventListener('click', () => {
  enabledToggle.checked = DEFAULTS.enabled;
  autoFitCheck.checked = DEFAULTS.autoFit;
  minHeightSlider.value = DEFAULTS.minHeight;
  showHighlightCheck.checked = DEFAULTS.showHighlight;
  heightVal.textContent = DEFAULTS.minHeight + 'px';
  customFields = [];
  renderCustomFields();
  saveSettings();
});

// Targets accordion
targetsToggle.addEventListener('click', () => {
  const isOpen = targetsList.classList.toggle('open');
  targetsArrow.classList.toggle('open', isOpen);
  targetsToggle.setAttribute('aria-expanded', String(isOpen));
});
