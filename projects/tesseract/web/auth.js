/**
 * auth.js — Tesseract 4D Authentication Logic
 * Handles Login, Register, and Password Reset using the DartStream backend APIs.
 */

// ─── State ────────────────────────────────────────────────────────────────────
let currentTab = 'login';

// ─── Animated 4D Background ───────────────────────────────────────────────────
(function initBgCanvas() {
  const canvas = document.getElementById('bg-canvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');

  function resize() {
    canvas.width  = window.innerWidth;
    canvas.height = window.innerHeight;
  }
  resize();
  window.addEventListener('resize', resize);

  // Minimal tesseract vertices for background animation
  const verts4D = [];
  for (let x of [-1, 1]) for (let y of [-1, 1]) for (let z of [-1, 1]) for (let w of [-1, 1]) {
    verts4D.push([x, y, z, w]);
  }
  const edges = [];
  for (let i = 0; i < 16; i++) for (let j = i + 1; j < 16; j++) {
    let d = 0;
    for (let k = 0; k < 4; k++) if (verts4D[i][k] !== verts4D[j][k]) d++;
    if (d === 1) edges.push([i, j]);
  }

  let angle = 0;

  function rotate4D(p, a) {
    let [x, y, z, w] = p;
    // slow XY rotation
    const c1 = Math.cos(a), s1 = Math.sin(a);
    [x, y] = [x * c1 - y * s1, x * s1 + y * c1];
    // slow ZW rotation
    const c2 = Math.cos(a * 0.7), s2 = Math.sin(a * 0.7);
    [z, w] = [z * c2 - w * s2, z * s2 + w * c2];
    return [x, y, z, w];
  }

  function project([x, y, z, w]) {
    const dW = 2.5, dZ = 3.0;
    const fW = dW / (dW - w);
    const x3 = x * fW, y3 = y * fW, z3 = z * fW;
    const fZ = dZ / (dZ - z3);
    const scale = Math.min(canvas.width, canvas.height) * 0.18;
    return {
      x: canvas.width  / 2 + x3 * fZ * scale,
      y: canvas.height / 2 + y3 * fZ * scale,
    };
  }

  function draw() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    angle += 0.003;
    const proj = verts4D.map(v => project(rotate4D(v, angle)));

    ctx.lineWidth = 1;
    for (const [i, j] of edges) {
      const p1 = proj[i], p2 = proj[j];
      const isInner = verts4D[i][3] < 0 && verts4D[j][3] < 0;
      ctx.strokeStyle = isInner
        ? 'rgba(184,0,255,0.06)'
        : 'rgba(0,242,254,0.06)';
      ctx.beginPath();
      ctx.moveTo(p1.x, p1.y);
      ctx.lineTo(p2.x, p2.y);
      ctx.stroke();
    }
    requestAnimationFrame(draw);
  }
  draw();
})();

// ─── Tab Switching ────────────────────────────────────────────────────────────
function switchTab(tab) {
  currentTab = tab;

  // Update tab buttons (only login/register have tab buttons)
  document.querySelectorAll('.auth-tab').forEach(t => {
    t.classList.remove('active');
    t.setAttribute('aria-selected', 'false');
  });

  const tabBtn = document.getElementById(`tab-${tab}`);
  if (tabBtn) {
    tabBtn.classList.add('active');
    tabBtn.setAttribute('aria-selected', 'true');
  }

  // Update panels
  document.querySelectorAll('.auth-panel').forEach(p => p.classList.remove('active'));
  const panel = document.getElementById(`panel-${tab}`);
  if (panel) panel.classList.add('active');

  // Clear all alerts
  clearAlert('login-alert');
  clearAlert('register-alert');
  clearAlert('reset-alert');
}

// ─── Alert Helpers ────────────────────────────────────────────────────────────
function showAlert(id, message, type = 'error') {
  const el = document.getElementById(id);
  if (!el) return;
  el.className = `auth-alert ${type}`;
  el.textContent = message;
}

function clearAlert(id) {
  const el = document.getElementById(id);
  if (!el) return;
  el.className = 'auth-alert';
  el.textContent = '';
}

// ─── Loading State ────────────────────────────────────────────────────────────
function setLoading(btnId, isLoading) {
  const btn = document.getElementById(btnId);
  if (!btn) return;
  btn.disabled = isLoading;
  if (isLoading) {
    btn.classList.add('loading');
  } else {
    btn.classList.remove('loading');
  }
}

// ─── Password Visibility Toggle ───────────────────────────────────────────────
function togglePassword(inputId, btn) {
  const input = document.getElementById(inputId);
  if (!input) return;
  const isHidden = input.type === 'password';
  input.type = isHidden ? 'text' : 'password';
  btn.textContent = isHidden ? '🙈' : '👁';
}

// ─── Password Strength Meter ──────────────────────────────────────────────────
function evaluateStrength(password) {
  let score = 0;
  if (password.length >= 8)  score++;
  if (password.length >= 12) score++;
  if (/[A-Z]/.test(password) && /[a-z]/.test(password)) score++;
  if (/[0-9]/.test(password)) score++;
  if (/[^A-Za-z0-9]/.test(password)) score++;
  return Math.min(score, 4);
}

const passwordInput = document.getElementById('register-password');
if (passwordInput) {
  passwordInput.addEventListener('input', () => {
    const val = passwordInput.value;
    const score = evaluateStrength(val);
    const bars  = [document.getElementById('sb1'), document.getElementById('sb2'),
                   document.getElementById('sb3'), document.getElementById('sb4')];
    const label = document.getElementById('strength-label');
    const classes = ['', 'weak', 'medium', 'medium', 'strong'];
    const labels  = ['', 'Weak', 'Fair', 'Good', 'Strong'];

    bars.forEach((bar, i) => {
      bar.className = 'strength-bar';
      if (i < score && val.length > 0) {
        bar.classList.add(classes[score]);
      }
    });

    if (label) {
      label.textContent = val.length > 0 ? labels[score] : '';
      const colors = { Weak: 'var(--danger)', Fair: '#F59E0B', Good: '#F59E0B', Strong: 'var(--success)' };
      label.style.color = colors[labels[score]] || 'var(--text-muted)';
    }
  });
}

// ─── Session Management ───────────────────────────────────────────────────────
function saveSession(data) {
  sessionStorage.setItem('ds_session', JSON.stringify(data));
}

function redirectToGame() {
  window.location.replace('index.html');
}

// ─── Friendly Error Messages ──────────────────────────────────────────────────
function friendlyError(raw) {
  const msg = (raw || '').toLowerCase();
  if (msg.includes('email_exists') || msg.includes('email already'))       return 'An account with this email already exists. Try signing in instead.';
  if (msg.includes('invalid_password') || msg.includes('wrong password') || msg.includes('invalid login credentials')) return 'Incorrect password. Please try again.';
  if (msg.includes('email_not_found') || msg.includes('no user record'))   return 'No account found with that email. Create one first.';
  if (msg.includes('too_many_attempts'))  return 'Too many failed attempts. Please wait a moment and try again.';
  if (msg.includes('weak_password'))      return 'Password is too weak. Use at least 8 characters with mixed case and numbers.';
  if (msg.includes('invalid_email'))      return 'Please enter a valid email address.';
  if (msg.includes('network') || msg.includes('failed to fetch')) return 'Network error — check your connection and try again.';
  if (msg.includes('user_disabled'))      return 'This account has been disabled. Contact support.';
  return raw || 'An unexpected error occurred. Please try again.';
}

// ─── API Calls ────────────────────────────────────────────────────────────────
async function apiPost(path, body) {
  try {
    const response = await fetch(path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    
    const contentType = response.headers.get('content-type') || '';
    if (contentType.includes('text/html')) {
      throw new Error('Server returned HTML instead of JSON. The backend server might be offline.');
    }
    
    const data = await response.json().catch(() => ({}));
    return { ok: response.ok, status: response.status, data };
  } catch (err) {
    return { ok: false, status: 500, data: { error: err.message } };
  }
}

// ─── Login Handler ────────────────────────────────────────────────────────────
document.getElementById('login-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  clearAlert('login-alert');

  const email    = document.getElementById('login-email').value.trim();
  const password = document.getElementById('login-password').value;

  if (!email || !password) {
    showAlert('login-alert', 'Please enter your email and password.');
    return;
  }

  setLoading('login-btn', true);

  try {
    const { ok, data } = await apiPost('/api/auth/login', { email, password });

    if (ok && data.idToken) {
      saveSession({ idToken: data.idToken, userId: data.userId, email: data.email });
      showAlert('login-alert', 'Login successful! Launching game...', 'success');
      setTimeout(redirectToGame, 600);
    } else {
      const errorMsg = data.error || data.message || 'Login failed.';
      showAlert('login-alert', friendlyError(errorMsg));
      document.getElementById('login-password').classList.add('error');
    }
  } catch (err) {
    showAlert('login-alert', friendlyError(err.message));
  } finally {
    setLoading('login-btn', false);
  }
});

document.getElementById('login-password').addEventListener('input', () => {
  document.getElementById('login-password').classList.remove('error');
});

// ─── Register Handler ─────────────────────────────────────────────────────────
document.getElementById('register-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  clearAlert('register-alert');

  const email    = document.getElementById('register-email').value.trim();
  const password = document.getElementById('register-password').value;
  const confirm  = document.getElementById('register-confirm').value;

  if (!email || !password || !confirm) {
    showAlert('register-alert', 'Please fill in all fields.');
    return;
  }

  if (password.length < 8) {
    showAlert('register-alert', 'Password must be at least 8 characters.');
    return;
  }

  if (password !== confirm) {
    showAlert('register-alert', 'Passwords do not match.');
    document.getElementById('register-confirm').classList.add('error');
    return;
  }

  setLoading('register-btn', true);

  try {
    const { ok, data } = await apiPost('/api/auth/register', { email, password });

    if (ok && data.idToken) {
      saveSession({ idToken: data.idToken, userId: data.userId, email: data.email });
      showAlert('register-alert', 'Account created! Launching game...', 'success');
      setTimeout(redirectToGame, 700);
    } else {
      const errorMsg = data.error || data.message || 'Registration failed.';
      showAlert('register-alert', friendlyError(errorMsg));
    }
  } catch (err) {
    showAlert('register-alert', friendlyError(err.message));
  } finally {
    setLoading('register-btn', false);
  }
});

document.getElementById('register-confirm').addEventListener('input', () => {
  document.getElementById('register-confirm').classList.remove('error');
});

// ─── Password Reset Handler ───────────────────────────────────────────────────
document.getElementById('reset-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  clearAlert('reset-alert');

  const email = document.getElementById('reset-email').value.trim();
  if (!email) {
    showAlert('reset-alert', 'Please enter your email address.');
    return;
  }

  setLoading('reset-btn', true);

  try {
    const { ok, data } = await apiPost('/api/auth/reset-password', { email });
    if (ok) {
      showAlert('reset-alert', `Reset link sent to ${email}. Check your inbox.`, 'success');
    } else {
      const errorMsg = data.error || data.message || 'Failed to send reset email.';
      showAlert('reset-alert', friendlyError(errorMsg));
    }
  } catch (err) {
    showAlert('reset-alert', friendlyError(err.message));
  } finally {
    setLoading('reset-btn', false);
  }
});

// ─── Redirect Authenticated Users ─────────────────────────────────────────────
(function checkExistingSession() {
  const session = sessionStorage.getItem('ds_session');
  if (session) {
    // Already logged in — go straight to the game
    window.location.replace('index.html');
  }
})();
