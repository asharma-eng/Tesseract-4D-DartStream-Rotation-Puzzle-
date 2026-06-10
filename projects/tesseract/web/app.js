document.addEventListener('DOMContentLoaded', () => {
  // Elements
  const levelDisplay = document.getElementById('level-display');
  const rotationsDisplay = document.getElementById('rotations-display');
  const timerDisplay = document.getElementById('timer-display');
  const matchDisplay = document.getElementById('match-display');
  const winOverlay = document.getElementById('win-overlay');
  const nextLevelBtn = document.getElementById('next-level-btn');
  const resetAnglesBtn = document.getElementById('reset-angles-btn');
  
  // Sliders
  const sliders = {
    xy: document.getElementById('slider-xy'),
    xz: document.getElementById('slider-xz'),
    yz: document.getElementById('slider-yz'),
    xw: document.getElementById('slider-xw'),
    yw: document.getElementById('slider-yw'),
    zw: document.getElementById('slider-zw')
  };
  const valDisplays = {
    xy: document.getElementById('val-xy'),
    xz: document.getElementById('val-xz'),
    yz: document.getElementById('val-yz'),
    xw: document.getElementById('val-xw'),
    yw: document.getElementById('val-yw'),
    zw: document.getElementById('val-zw')
  };

  // Feature Flags
  const flagWaxis = document.getElementById('flag-waxis');
  const flagReference = document.getElementById('flag-reference');
  const flagHypercolor = document.getElementById('flag-hypercolor');
  const flagDifficulty = document.getElementById('flag-difficulty');
  const flagsStatus = document.getElementById('flags-status');

  // Canvases
  const gameCanvas = document.getElementById('game-canvas');
  const gameCtx = gameCanvas.getContext('2d');
  const targetCanvas = document.getElementById('target-canvas');
  const targetCtx = targetCanvas.getContext('2d');
  const targetReferenceCard = document.getElementById('target-reference-card');

  // Chat
  const chatMessages = document.getElementById('chat-messages-container');
  const chatForm = document.getElementById('chat-form');
  const chatInput = document.getElementById('chat-input');
  const chipPrompts = document.querySelectorAll('.chip-prompt');

  // Terminal Log
  const terminalLog = document.getElementById('terminal-log');
  const sseStatus = document.getElementById('sse-status');

  // Game States
  let level = 1;
  let rotations = 0;
  let secondsElapsed = 0;
  let gameTimer = null;
  let sseConnection = null;
  let levelCleared = false;

  let activeFlags = {
    enableWaxisRotation: true,
    showTargetReference: true,
    hypercolorMode: false,
    hardcoreDifficulty: false
  };

  // 4D Hypercube definition
  // A tesseract has 16 vertices: combinations of (+-1, +-1, +-1, +-1)
  const vertices = [];
  for (let x of [-1, 1]) {
    for (let y of [-1, 1]) {
      for (let z of [-1, 1]) {
        for (let w of [-1, 1]) {
          vertices.push([x, y, z, w]);
        }
      }
    }
  }

  // 32 Edges: connect if vertices differ by exactly one coordinate (distance == 2)
  const edges = [];
  for (let i = 0; i < 16; i++) {
    for (let j = i + 1; j < 16; j++) {
      let diffCount = 0;
      for (let k = 0; k < 4; k++) {
        if (vertices[i][k] !== vertices[j][k]) diffCount++;
      }
      if (diffCount === 1) {
        edges.push([i, j]);
      }
    }
  }

  // Rotational State (current and target blueprint)
  let userAngles = { xy: 0, xz: 0, yz: 0, xw: 0, yw: 0, zw: 0 };
  let targetAngles = { xy: 0, xz: 0, yz: 0, xw: 0, yw: 0, zw: 0 };

  // 1. Math - 4D Rotations and Projections
  function rotate4D(point, angles) {
    let [x, y, z, w] = point;

    // XY plane rotation
    if (angles.xy !== 0) {
      const rad = angles.xy * Math.PI / 180;
      const nx = x * Math.cos(rad) - y * Math.sin(rad);
      const ny = x * Math.sin(rad) + y * Math.cos(rad);
      x = nx; y = ny;
    }
    // XZ plane
    if (angles.xz !== 0) {
      const rad = angles.xz * Math.PI / 180;
      const nx = x * Math.cos(rad) - z * Math.sin(rad);
      const nz = x * Math.sin(rad) + z * Math.cos(rad);
      x = nx; z = nz;
    }
    // YZ plane
    if (angles.yz !== 0) {
      const rad = angles.yz * Math.PI / 180;
      const ny = y * Math.cos(rad) - z * Math.sin(rad);
      const nz = y * Math.sin(rad) + z * Math.cos(rad);
      y = ny; z = nz;
    }
    // XW plane
    if (angles.xw !== 0) {
      const rad = angles.xw * Math.PI / 180;
      const nx = x * Math.cos(rad) - w * Math.sin(rad);
      const nw = x * Math.sin(rad) + w * Math.cos(rad);
      x = nx; w = nw;
    }
    // YW plane
    if (angles.yw !== 0) {
      const rad = angles.yw * Math.PI / 180;
      const ny = y * Math.cos(rad) - w * Math.sin(rad);
      const nw = y * Math.sin(rad) + w * Math.cos(rad);
      y = ny; w = nw;
    }
    // ZW plane
    if (angles.zw !== 0) {
      const rad = angles.zw * Math.PI / 180;
      const nz = z * Math.cos(rad) - w * Math.sin(rad);
      const nw = z * Math.sin(rad) + w * Math.cos(rad);
      z = nz; w = nw;
    }

    return [x, y, z, w];
  }

  // Perspective project: 4D -> 3D -> 2D
  function projectPoint(point, width, height) {
    const [x, y, z, w] = point;

    // 1. Perspective project 4D -> 3D (W-axis distance)
    const distanceW = 2.2;
    const factorW = distanceW / (distanceW - w);
    const x3d = x * factorW;
    const y3d = y * factorW;
    const z3d = z * factorW;

    // 2. Perspective project 3D -> 2D (Z-axis distance)
    const distanceZ = 2.5;
    const factorZ = distanceZ / (distanceZ - z3d);
    
    // Scale and translate to canvas center
    const scale = Math.min(width, height) * 0.22;
    const screenX = width / 2 + x3d * factorZ * scale;
    const screenY = height / 2 + y3d * factorZ * scale;

    return { x: screenX, y: screenY };
  }

  // 2. Rendering loops
  function drawTesseract(ctx, canvas, angles) {
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    const projected = [];
    const colors = activeFlags.hypercolorMode ? getHypercolors() : getStandardColors();

    // 1. Project all rotated vertices
    for (let vertex of vertices) {
      const rotated = rotate4D(vertex, angles);
      projected.push(projectPoint(rotated, canvas.width, canvas.height));
    }

    // 2. Draw Edges
    ctx.lineWidth = canvas.width > 300 ? 1.5 : 1.0;
    for (let edge of edges) {
      const p1 = projected[edge[0]];
      const p2 = projected[edge[1]];

      // Check edge depth by average Z-depth of vertices to add opacity depth
      const rotV1 = rotate4D(vertices[edge[0]], angles);
      const rotV2 = rotate4D(vertices[edge[1]], angles);
      const avgZ = (rotV1[2] + rotV2[2]) / 2;
      const alpha = Math.max(0.2, Math.min(1.0, (avgZ + 2.5) / 5));

      // Differentiate inner and outer hypercube edges via color
      const isInner = (vertices[edge[0]][3] < 0 && vertices[edge[1]][3] < 0);
      ctx.strokeStyle = isInner ? colors.inner(alpha) : colors.outer(alpha);

      ctx.beginPath();
      ctx.moveTo(p1.x, p1.y);
      ctx.lineTo(p2.x, p2.y);
      ctx.stroke();
    }

    // 3. Draw Vertices (nodes)
    const nodeRadius = canvas.width > 300 ? 4 : 2;
    for (let i = 0; i < projected.length; i++) {
      const p = projected[i];
      const wDepth = vertices[i][3]; // use w depth to set color/radius
      ctx.beginPath();
      ctx.arc(p.x, p.y, nodeRadius, 0, 2 * Math.PI);
      ctx.fillStyle = wDepth < 0 ? colors.innerNode : colors.outerNode;
      ctx.fill();
    }
  }

  function getStandardColors() {
    const cyan = getComputedStyle(document.body).getPropertyValue('--accent-cyan').trim() || '#00F2FE';
    const purple = getComputedStyle(document.body).getPropertyValue('--accent-purple').trim() || '#B800FF';
    return {
      inner: (a) => hexToRgbA(purple, a),
      outer: (a) => hexToRgbA(cyan, a),
      innerNode: purple,
      outerNode: cyan
    };
  }

  function getHypercolors() {
    const time = Date.now() * 0.001;
    const hue1 = (time * 20) % 360;
    const hue2 = (time * 20 + 120) % 360;
    return {
      inner: (a) => `hsla(${hue1}, 80%, 60%, ${a})`,
      outer: (a) => `hsla(${hue2}, 85%, 55%, ${a})`,
      innerNode: `hsl(${hue1}, 80%, 60%)`,
      outerNode: `hsl(${hue2}, 85%, 55%)`
    };
  }

  function hexToRgbA(hex, alpha) {
    if (/^#([A-Fa-f0-9]{3}){1,2}$/.test(hex)) {
      let c = hex.substring(1).split('');
      if (c.length === 3) {
        c = [c[0], c[0], c[1], c[1], c[2], c[2]];
      }
      c = '0x' + c.join('');
      return 'rgba(' + [(c >> 16) & 255, (c >> 8) & 255, c & 255].join(',') + ',' + alpha + ')';
    }
    return hex;
  }

  // 3. Gameplay Mechanics & Engine Loops
  function startNewLevel() {
    levelCleared = false;
    winOverlay.style.display = 'none';

    // Generate random target rotation angles
    // 3D planes
    targetAngles.xy = getRandomRotation();
    targetAngles.xz = getRandomRotation();
    targetAngles.yz = getRandomRotation();

    // 4D planes (XW, YW, ZW)
    if (activeFlags.enableWaxisRotation) {
      targetAngles.xw = getRandomRotation();
      targetAngles.yw = getRandomRotation();
      targetAngles.zw = getRandomRotation();
    } else {
      targetAngles.xw = 0;
      targetAngles.yw = 0;
      targetAngles.zw = 0;
    }

    // Reset user sliders
    for (let key in sliders) {
      sliders[key].value = 0;
      userAngles[key] = 0;
      valDisplays[key].innerText = '0°';
    }

    rotations = 0;
    rotationsDisplay.innerText = rotations;

    // Report starting game telemetry
    submitTelemetry('level_start', `Starting decryption lock for Level ${level}`);

    // Initial render
    updateGameDrawing();
  }

  function getRandomRotation() {
    // Return steps of 45 degs to make it alignable
    const steps = [-135, -90, -45, 0, 45, 90, 135];
    return steps[Math.floor(Math.random() * steps.length)];
  }

  function updateGameDrawing() {
    drawTesseract(gameCtx, gameCanvas, userAngles);
    
    if (activeFlags.showTargetReference) {
      drawTesseract(targetCtx, targetCanvas, targetAngles);
    } else {
      // Clear target canvas if reference hidden
      targetCtx.clearRect(0, 0, targetCanvas.width, targetCanvas.height);
    }

    checkAlignment();
  }

  // Alignment Checker: evaluates average screen distances between user and target vertices
  function checkAlignment() {
    if (levelCleared) return;

    let userProjected = [];
    let targetProjected = [];

    // Calculate rotated projection coordinates
    for (let vertex of vertices) {
      const rUser = rotate4D(vertex, userAngles);
      const rTarget = rotate4D(vertex, targetAngles);
      userProjected.push(projectPoint(rUser, gameCanvas.width, gameCanvas.height));
      targetProjected.push(projectPoint(rTarget, gameCanvas.width, gameCanvas.height));
    }

    // Compute average distance sum
    let distanceSum = 0;
    for (let i = 0; i < 16; i++) {
      const dx = userProjected[i].x - targetProjected[i].x;
      const dy = userProjected[i].y - targetProjected[i].y;
      distanceSum += Math.sqrt(dx * dx + dy * dy);
    }

    // Convert sum to percentage
    // Low average distances maps to higher percentage matches
    const avgDistance = distanceSum / 16;
    let matchPercent = Math.max(0, Math.min(100, Math.round(100 - (avgDistance * 1.5))));
    matchDisplay.innerText = `${matchPercent}%`;

    // Tolerance threshold checks
    const tolerance = activeFlags.hardcoreDifficulty ? 98 : 95; // 2% or 5% tolerance
    if (matchPercent >= tolerance) {
      triggerWin();
    }
  }

  function triggerWin() {
    levelCleared = true;
    winOverlay.style.display = 'flex';
    
    submitTelemetry('level_win', `Decrypt lock Level ${level} cleared! Score: ${secondsElapsed}s.`, secondsElapsed);

    appendTerminalLine(new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }), `[SUCCESS] Decryption matched at Level ${level}.`, 'win-msg');
  }

  // Submit telemetry data package to DartStream Backend API
  async function submitTelemetry(type, message, score = 0) {
    try {
      await fetch('/api/game/telemetry', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          type: type,
          level: level,
          rotations: rotations,
          score: score,
          message: message
        })
      });
    } catch (e) {
      console.error('Telemetry submit failed:', e);
    }
  }

  // 4. API - Sync Feature Flags
  async function loadFeatureFlags() {
    try {
      flagsStatus.innerText = 'SYNCING...';
      const response = await fetch('/api/features');
      if (response.ok) {
        const flags = await response.json();
        activeFlags = { ...activeFlags, ...flags };
        
        flagWaxis.checked = activeFlags.enableWaxisRotation;
        flagReference.checked = activeFlags.showTargetReference;
        flagHypercolor.checked = activeFlags.hypercolorMode;
        flagDifficulty.checked = activeFlags.hardcoreDifficulty;

        applyFeatureFlags();
        flagsStatus.innerText = 'SYNCED';
      }
    } catch (e) {
      flagsStatus.innerText = 'OFFLINE';
    }
  }

  async function updateFeatureFlag(key, value) {
    try {
      flagsStatus.innerText = 'SYNCING...';
      activeFlags[key] = value;
      applyFeatureFlags();

      const response = await fetch('/api/features', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ [key]: value })
      });

      if (response.ok) {
        flagsStatus.innerText = 'SYNCED';
      } else {
        flagsStatus.innerText = 'ERROR';
      }
    } catch (e) {
      flagsStatus.innerText = 'ERROR';
    }
  }

  function applyFeatureFlags() {
    // Toggle 4D Sliders
    const wControls = document.querySelectorAll('.w-axis-control');
    wControls.forEach(ctrl => {
      const input = ctrl.querySelector('input');
      if (activeFlags.enableWaxisRotation) {
        ctrl.style.opacity = '1';
        input.disabled = false;
      } else {
        ctrl.style.opacity = '0.35';
        input.disabled = true;
        input.value = 0;
        userAngles[input.id.replace('slider-', '')] = 0;
        ctrl.querySelector('.plane-val').innerText = '0°';
      }
    });

    // Reference card display
    if (activeFlags.showTargetReference) {
      targetReferenceCard.style.display = 'flex';
    } else {
      targetReferenceCard.style.display = 'none';
    }

    // Dynamic hypercolor hues trigger
    if (activeFlags.hypercolorMode) {
      document.body.classList.add('hypercolor-active');
    } else {
      document.body.classList.remove('hypercolor-active');
    }

    updateGameDrawing();
  }

  // 5. Setup Server-Sent Events (SSE) Stream Listener
  function initTelemetryStream() {
    if (sseConnection) {
      sseConnection.close();
    }

    sseStatus.innerText = 'CONNECTING...';
    sseStatus.className = 'badge badge-outline';

    sseConnection = new EventSource('/api/stream');

    sseConnection.onopen = () => {
      sseStatus.innerText = 'ACTIVE';
      sseStatus.className = 'badge text-cyan';
      appendTerminalLine('System', 'Event Broadcast pipeline initialized.', 'system-msg');
    };

    sseConnection.onerror = () => {
      sseStatus.innerText = 'RECONNECTING';
      sseStatus.className = 'badge text-purple';
    };

    sseConnection.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        const time = data.timestamp ? data.timestamp.split('T')[1].substring(0, 8) : '00:00:00';

        if (data.type === 'keep_alive') {
          // ignore or keep log clean
          return;
        }

        if (data.type === 'flag_update') {
          activeFlags = { ...activeFlags, ...data.flags };
          flagWaxis.checked = activeFlags.enableWaxisRotation;
          flagReference.checked = activeFlags.showTargetReference;
          flagHypercolor.checked = activeFlags.hypercolorMode;
          flagDifficulty.checked = activeFlags.hardcoreDifficulty;
          applyFeatureFlags();
          appendTerminalLine(time, `[FLAG UPDATE] Flags synchronized across cluster.`);
          return;
        }

        if (data.type === 'level_win') {
          appendTerminalLine(time, `[STREAM] Level win broadcast: score ${data.score}s.`, 'win-msg');
          return;
        }

        // Print general incoming telemetry logs to console panel
        if (data.message) {
          appendTerminalLine(time, `[STREAM] Event: ${data.message}`);
        }
      } catch (e) {
        console.error('SSE data error:', e);
      }
    };
  }

  function appendTerminalLine(timestamp, text, typeClass = '') {
    const line = document.createElement('div');
    line.className = `log-line ${typeClass}`;
    
    const timeSpan = document.createElement('span');
    timeSpan.className = 'timestamp';
    timeSpan.innerText = `[${timestamp}]`;

    const msgSpan = document.createElement('span');
    msgSpan.className = 'message';
    msgSpan.innerText = text;

    line.appendChild(timeSpan);
    line.appendChild(msgSpan);
    terminalLog.appendChild(line);

    terminalLog.scrollTop = terminalLog.scrollHeight;

    if (terminalLog.children.length > 30) {
      terminalLog.removeChild(terminalLog.firstChild);
    }
  }

  // 6. AI assistant handlers
  async function handleSendMessage(message) {
    if (!message.trim()) return;

    appendChatBubble('user', message);
    chatInput.value = '';
    chatMessages.scrollTop = chatMessages.scrollHeight;

    const typingBubble = appendChatBubble('assistant typing', `
      <div class="typing-indicator">
        <span></span><span></span><span></span>
      </div>
    `, true);

    try {
      const response = await fetch('/api/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: message })
      });

      typingBubble.remove();

      if (response.ok) {
        const data = await response.json();
        appendChatBubble('assistant', data.reply);
      } else {
        appendChatBubble('assistant', 'Game Master telemetry offline.');
      }
    } catch (e) {
      typingBubble.remove();
      appendChatBubble('assistant', 'Connection to Game Master timed out.');
    }

    chatMessages.scrollTop = chatMessages.scrollHeight;
  }

  function appendChatBubble(sender, content, isHtml = false) {
    const bubble = document.createElement('div');
    bubble.className = `chat-bubble ${sender}`;

    const contentDiv = document.createElement('div');
    contentDiv.className = 'bubble-content';
    if (isHtml) {
      contentDiv.innerHTML = content;
    } else {
      contentDiv.innerText = content;
    }

    const timeSpan = document.createElement('span');
    timeSpan.className = 'chat-time';
    timeSpan.innerText = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

    bubble.appendChild(contentDiv);
    bubble.appendChild(timeSpan);
    chatMessages.appendChild(bubble);
    
    return bubble;
  }

  // 7. Event listeners
  for (let key in sliders) {
    sliders[key].addEventListener('input', (e) => {
      userAngles[key] = parseInt(e.target.value);
      valDisplays[key].innerText = `${e.target.value}°`;
      updateGameDrawing();
    });

    sliders[key].addEventListener('change', () => {
      // Record a rotation count increase on mouse release/change end
      rotations++;
      rotationsDisplay.innerText = rotations;
      submitTelemetry('rotate', `User rotated ${key} plane to ${userAngles[key]}°`);
    });
  }

  resetAnglesBtn.addEventListener('click', () => {
    for (let key in sliders) {
      sliders[key].value = 0;
      userAngles[key] = 0;
      valDisplays[key].innerText = '0°';
    }
    updateGameDrawing();
  });

  nextLevelBtn.addEventListener('click', () => {
    level++;
    levelDisplay.innerText = level;
    startNewLevel();
  });

  // Feature Flag UI triggers
  flagWaxis.addEventListener('change', (e) => {
    updateFeatureFlag('enableWaxisRotation', e.target.checked);
  });
  flagReference.addEventListener('change', (e) => {
    updateFeatureFlag('showTargetReference', e.target.checked);
  });
  flagHypercolor.addEventListener('change', (e) => {
    updateFeatureFlag('hypercolorMode', e.target.checked);
  });
  flagDifficulty.addEventListener('change', (e) => {
    updateFeatureFlag('hardcoreDifficulty', e.target.checked);
  });

  chatForm.addEventListener('submit', (e) => {
    e.preventDefault();
    handleSendMessage(chatInput.value);
  });

  chipPrompts.forEach(chip => {
    chip.addEventListener('click', () => {
      handleSendMessage(chip.getAttribute('data-msg'));
    });
  });

  // Game Timer loop
  function startTimer() {
    if (gameTimer) clearInterval(gameTimer);
    secondsElapsed = 0;
    gameTimer = setInterval(() => {
      secondsElapsed++;
      const mins = Math.floor(secondsElapsed / 60).toString().padStart(2, '0');
      const secs = (secondsElapsed % 60).toString().padStart(2, '0');
      timerDisplay.innerText = `${mins}:${secs}`;
    }, 1000);
  }

  // Hypercolor drawing loop to refresh line hues continuously
  function animateHypercolors() {
    if (activeFlags.hypercolorMode) {
      updateGameDrawing();
    }
    requestAnimationFrame(animateHypercolors);
  }

  // Initialize Game
  startTimer();
  loadFeatureFlags();
  initTelemetryStream();
  startNewLevel();
  animateHypercolors();
});
