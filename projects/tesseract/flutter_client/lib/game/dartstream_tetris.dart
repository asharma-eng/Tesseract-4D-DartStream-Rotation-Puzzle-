import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Gameplay configuration derived from live DartStream services:
/// - feature flags toggle the rules (double score, hard mode, extra life),
/// - inventory grants the sword ability (clear bottom 3 rows),
/// - a cloud-save snapshot resumes the high score / lifetime coins (represented as cleared lines).
class TetrisConfig {
  const TetrisConfig({
    this.startLives = 3,
    this.doubleScore = false,
    this.hardMode = false,
    this.swordCharges = 0,
    this.resumeHighScore = 0,
    this.resumeLifetimeCoins = 0,
    this.playerName = 'Player',
  });

  final int startLives;
  final bool doubleScore;
  final bool hardMode;
  final int swordCharges;
  final int resumeHighScore;
  final int resumeLifetimeCoins;
  final String playerName;
}

/// "DartStream Tetris" — classic block stacking game. Every gameplay
/// beat is wired to a DartStream service via [onSnapshot] (cloud-save) and
/// [onEvent] (reactive event log).
class DartstreamTetrisGame extends FlameGame
    with TapCallbacks, DragCallbacks, KeyboardEvents {
  DartstreamTetrisGame({
    required this.config,
    required this.onSnapshot,
    required this.onEvent,
  });

  final TetrisConfig config;
  final void Function(Map<String, dynamic> snapshot) onSnapshot;
  final void Function(String type, Map<String, dynamic> payload) onEvent;

  // Board dimensions
  static const int cols = 10;
  static const int rows = 20;

  // Game board grid (0 = empty, 1-7 = tetrominoes, 8 = grey garbage)
  late List<List<int>> board;

  // Scoring and progression
  int score = 0;
  int level = 1;
  int coins = 0; // mapped to total cleared lines for cloud save compatibility
  int lives = 3;
  int highScore = 0;
  int lifetimeCoins = 0; // mapped to total cleared lines
  int swordCharges = 0;
  bool gameOver = false;

  // Active falling piece details
  late List<List<int>> currentPiece;
  late int currentPieceType;
  int currentX = 0;
  int currentY = 0;

  // Upcoming and held pieces
  late List<List<int>> nextPiece;
  late int nextPieceType;
  List<List<int>>? heldPiece;
  int? heldPieceType;
  bool canHold = true;

  // Timers and game loop variables
  double _fallTimer = 0.0;
  double _garbageTimer = 0.0;
  final math.Random _rng = math.Random();

  // Visual effects
  bool _showResurrectBanner = false;
  double _resurrectBannerTimer = 0.0;
  bool _showSwordEffect = false;
  double _swordEffectTimer = 0.0;

  // Text renderers
  late TextPaint _textRenderer;
  late TextPaint _titleRenderer;

  // Layout sizing
  double _cellSize = 0.0;
  double _boardWidth = 0.0;
  double _boardHeight = 0.0;
  double _boardLeft = 0.0;
  double _boardTop = 0.0;

  // Standard Tetromino shapes (matrix-based for rotation)
  static const List<List<List<int>>> tetrominoes = [
    // 1: I-shape (Cyan)
    [
      [0, 0, 0, 0],
      [1, 1, 1, 1],
      [0, 0, 0, 0],
      [0, 0, 0, 0],
    ],
    // 2: O-shape (Yellow)
    [
      [2, 2],
      [2, 2],
    ],
    // 3: T-shape (Purple)
    [
      [0, 3, 0],
      [3, 3, 3],
      [0, 0, 0],
    ],
    // 4: S-shape (Green)
    [
      [0, 4, 4],
      [4, 4, 0],
      [0, 0, 0],
    ],
    // 5: Z-shape (Red)
    [
      [5, 5, 0],
      [0, 5, 5],
      [0, 0, 0],
    ],
    // 6: J-shape (Blue)
    [
      [6, 0, 0],
      [6, 6, 6],
      [0, 0, 0],
    ],
    // 7: L-shape (Orange)
    [
      [0, 0, 7],
      [7, 7, 7],
      [0, 0, 0],
    ],
  ];

  double get _fallInterval {
    final baseSpeed = config.hardMode ? 0.45 : 0.8;
    final speedUp = (level - 1) * 0.07;
    return math.max(0.08, baseSpeed - speedUp);
  }

  @override
  Color backgroundColor() => const Color(0xFF0E1320);

  @override
  Future<void> onLoad() async {
    super.onLoad();
    _initGame();
  }

  void _initGame() {
    board = List.generate(rows, (_) => List.filled(cols, 0));
    score = 0;
    coins = 0;
    level = 1;
    lives = config.startLives;
    highScore = config.resumeHighScore;
    lifetimeCoins = config.resumeLifetimeCoins;
    swordCharges = config.swordCharges;
    gameOver = false;
    heldPiece = null;
    heldPieceType = null;
    canHold = true;

    _textRenderer = TextPaint(
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        fontFamily: 'Courier New',
      ),
    );

    _titleRenderer = TextPaint(
      style: const TextStyle(
        color: Color(0xFF3DBEFF),
        fontSize: 16,
        fontWeight: FontWeight.bold,
        fontFamily: 'Courier New',
      ),
    );

    // Seed next piece
    nextPieceType = _rng.nextInt(7) + 1;
    nextPiece = tetrominoes[nextPieceType - 1];

    _spawnPiece();

    onEvent('game.start', {
      'player': config.playerName,
      'doubleScore': config.doubleScore,
      'hardMode': config.hardMode,
      'startLives': lives,
      'swordCharges': swordCharges,
      'highScore': highScore,
    });
  }

  void _spawnPiece() {
    currentPiece = nextPiece;
    currentPieceType = nextPieceType;

    nextPieceType = _rng.nextInt(7) + 1;
    nextPiece = tetrominoes[nextPieceType - 1];

    currentX = (cols - currentPiece[0].length) ~/ 2;
    currentY = 0;

    canHold = true;

    // Check spawn collision right away
    if (_checkCollision(currentPiece, currentX, currentY)) {
      _handleLifeLossOrGameOver();
    }
  }

  bool _checkCollision(List<List<int>> piece, int px, int py) {
    for (int r = 0; r < piece.length; r++) {
      for (int c = 0; c < piece[r].length; c++) {
        if (piece[r][c] != 0) {
          int boardX = px + c;
          int boardY = py + r;

          if (boardX < 0 || boardX >= cols) return true;
          if (boardY >= rows) return true;
          if (boardY >= 0 && board[boardY][boardX] != 0) return true;
        }
      }
    }
    return false;
  }

  void _rotatePiece() {
    if (gameOver) return;
    // O shape doesn't need rotation
    if (currentPieceType == 2) return;

    final n = currentPiece.length;
    final rotated = List.generate(n, (_) => List.filled(n, 0));
    for (int r = 0; r < n; r++) {
      for (int c = 0; c < n; c++) {
        rotated[c][n - 1 - r] = currentPiece[r][c];
      }
    }

    // Try rotation; implement simple wall kick if colliding
    if (!_checkCollision(rotated, currentX, currentY)) {
      currentPiece = rotated;
    } else if (!_checkCollision(rotated, currentX - 1, currentY)) {
      currentX -= 1;
      currentPiece = rotated;
    } else if (!_checkCollision(rotated, currentX + 1, currentY)) {
      currentX += 1;
      currentPiece = rotated;
    } else if (!_checkCollision(rotated, currentX, currentY - 1)) {
      currentY -= 1;
      currentPiece = rotated;
    }
  }

  void _moveLeft() {
    if (gameOver) return;
    if (!_checkCollision(currentPiece, currentX - 1, currentY)) {
      currentX -= 1;
    }
  }

  void _moveRight() {
    if (gameOver) return;
    if (!_checkCollision(currentPiece, currentX + 1, currentY)) {
      currentX += 1;
    }
  }

  void _softDrop() {
    if (gameOver) return;
    if (!_checkCollision(currentPiece, currentX, currentY + 1)) {
      currentY += 1;
      score += 1;
      _fallTimer = 0.0; // reset gravity timer on manual drop
    } else {
      _lockPiece();
    }
  }

  void _hardDrop() {
    if (gameOver) return;
    int dropDist = 0;
    while (!_checkCollision(currentPiece, currentX, currentY + 1)) {
      currentY += 1;
      dropDist += 1;
    }
    score += dropDist * 2;
    _lockPiece();
  }

  void _holdPiece() {
    if (gameOver || !canHold) return;

    if (heldPiece == null) {
      heldPiece = tetrominoes[currentPieceType - 1];
      heldPieceType = currentPieceType;
      _spawnPiece();
    } else {
      final tempPiece = heldPiece!;
      final tempType = heldPieceType!;
      heldPiece = tetrominoes[currentPieceType - 1];
      heldPieceType = currentPieceType;

      currentPiece = tempPiece;
      currentPieceType = tempType;
      currentX = (cols - currentPiece[0].length) ~/ 2;
      currentY = 0;
    }

    canHold = false;
    _fallTimer = 0.0;
  }

  void _useSword() {
    if (gameOver || swordCharges <= 0) return;

    // Clear bottom 3 lines
    for (int i = 0; i < 3; i++) {
      board.removeAt(rows - 1);
      board.insert(0, List.filled(cols, 0));
    }

    swordCharges -= 1;
    _showSwordEffect = true;
    _swordEffectTimer = 0.6; // flash effect for 0.6s

    onEvent('game.sword.used', {
      'clearedLines': 3,
      'chargesLeft': swordCharges,
    });

    _emitSnapshot();
  }

  void _lockPiece() {
    // Write piece to board
    for (int r = 0; r < currentPiece.length; r++) {
      for (int c = 0; c < currentPiece[r].length; c++) {
        if (currentPiece[r][c] != 0) {
          int boardX = currentX + c;
          int boardY = currentY + r;
          if (boardY >= 0 && boardY < rows) {
            board[boardY][boardX] = currentPieceType;
          }
        }
      }
    }

    _clearLines();
    _spawnPiece();
    _emitSnapshot();
  }

  void _clearLines() {
    int cleared = 0;
    for (int r = rows - 1; r >= 0; r--) {
      bool full = true;
      for (int c = 0; c < cols; c++) {
        if (board[r][c] == 0) {
          full = false;
          break;
        }
      }
      if (full) {
        board.removeAt(r);
        board.insert(0, List.filled(cols, 0));
        cleared += 1;
        r++; // check this row index again since we shifted everything down
      }
    }

    if (cleared > 0) {
      int lineScore = switch (cleared) {
        1 => 100 * level,
        2 => 300 * level,
        3 => 500 * level,
        4 => 800 * level,
        _ => 1000 * level
      };

      if (config.doubleScore) {
        lineScore *= 2;
      }

      score += lineScore;
      coins += cleared;
      lifetimeCoins += cleared;

      if (score > highScore) {
        highScore = score;
      }

      // Check level up (every 10 lines)
      int oldLevel = level;
      level = 1 + (coins ~/ 10);
      if (level > oldLevel) {
        onEvent('game.level.up', {'level': level, 'score': score});
      }

      onEvent('game.line.clear', {
        'linesCleared': cleared,
        'level': level,
        'score': score,
      });
    }
  }

  void _handleLifeLossOrGameOver() {
    lives -= 1;
    onEvent('game.bomb.hit', {'livesLeft': lives, 'score': score});

    if (lives > 0) {
      // Clear board and resurrect
      board = List.generate(rows, (_) => List.filled(cols, 0));
      _showResurrectBanner = true;
      _resurrectBannerTimer = 2.0;

      // Reset falling piece positions
      currentX = (cols - currentPiece[0].length) ~/ 2;
      currentY = 0;
      _fallTimer = 0.0;
    } else {
      _endGame();
    }
    _emitSnapshot();
  }

  void _endGame() {
    gameOver = true;
    onEvent('game.over', {
      'score': score,
      'highScore': highScore,
      'level': level,
      'coins': coins,
      'lifetimeCoins': lifetimeCoins,
    });
  }

  void _restart() {
    if (!gameOver) return;
    _initGame();
  }

  void _emitSnapshot() {
    onSnapshot({
      'score': score,
      'highScore': highScore,
      'level': level,
      'lives': lives,
      'coins': coins,
      'lifetimeCoins': lifetimeCoins,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Update timers
    if (_showResurrectBanner) {
      _resurrectBannerTimer -= dt;
      if (_resurrectBannerTimer <= 0) {
        _showResurrectBanner = false;
      }
    }

    if (_showSwordEffect) {
      _swordEffectTimer -= dt;
      if (_swordEffectTimer <= 0) {
        _showSwordEffect = false;
      }
    }

    if (gameOver) return;

    // Gravity
    _fallTimer += dt;
    if (_fallTimer >= _fallInterval) {
      _fallTimer = 0.0;
      _softDrop();
    }

    // Hard Mode garbage line generator
    if (config.hardMode) {
      _garbageTimer += dt;
      if (_garbageTimer >= 15.0) {
        _garbageTimer = 0.0;
        _addGarbageRow();
      }
    }
  }

  void _addGarbageRow() {
    // Push everything up by 1
    board.removeAt(0);
    
    // Create new garbage row at bottom with 1 hole
    final garbageRow = List.filled(cols, 8); // 8 is grey block
    final holeCol = _rng.nextInt(cols);
    garbageRow[holeCol] = 0; // empty hole
    
    board.add(garbageRow);

    // Check if the current falling piece is now in a collision state
    if (_checkCollision(currentPiece, currentX, currentY)) {
      // try shifting current piece up, if it still collides, lose a life
      if (!_checkCollision(currentPiece, currentX, currentY - 1)) {
        currentY -= 1;
      } else {
        _handleLifeLossOrGameOver();
      }
    }
  }

  // Calculate coordinates of ghost piece
  int get _ghostY {
    int gy = currentY;
    while (!_checkCollision(currentPiece, currentX, gy + 1)) {
      gy += 1;
    }
    return gy;
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _calculateLayout();
  }

  void _calculateLayout() {
    _boardHeight = size.y - 70;
    if (_boardHeight < 200) _boardHeight = size.y - 20;
    _cellSize = _boardHeight / rows;
    _boardWidth = _cellSize * cols;
    _boardLeft = (size.x - _boardWidth) / 2;
    _boardTop = (size.y - _boardHeight) / 2;
  }

  // --- Rendering -------------------------------------------------------------

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Sizing check
    if (_cellSize <= 0) _calculateLayout();

    // 1. Draw Glassmorphic Game Board Background
    final boardRect = Rect.fromLTWH(_boardLeft, _boardTop, _boardWidth, _boardHeight);
    canvas.drawRect(boardRect, Paint()..color = const Color(0xFF13192B));

    // Draw grid border
    final borderPaint = Paint()
      ..color = const Color(0xFF1E294B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRect(boardRect, borderPaint);

    // Draw subtle grid lines
    final gridLinePaint = Paint()..color = const Color(0xFF171F36);
    for (int c = 1; c < cols; c++) {
      double lx = _boardLeft + c * _cellSize;
      canvas.drawLine(Offset(lx, _boardTop), Offset(lx, _boardTop + _boardHeight), gridLinePaint);
    }
    for (int r = 1; r < rows; r++) {
      double ly = _boardTop + r * _cellSize;
      canvas.drawLine(Offset(_boardLeft, ly), Offset(_boardLeft + _boardWidth, ly), gridLinePaint);
    }

    // 2. Draw Locked Blocks on Board
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (board[r][c] != 0) {
          _drawBlock(
            canvas,
            _boardLeft + c * _cellSize,
            _boardTop + r * _cellSize,
            _cellSize,
            board[r][c],
          );
        }
      }
    }

    if (!gameOver) {
      // 3. Draw Ghost Piece (Faint Projection)
      final gy = _ghostY;
      for (int r = 0; r < currentPiece.length; r++) {
        for (int c = 0; c < currentPiece[r].length; c++) {
          if (currentPiece[r][c] != 0) {
            final bx = _boardLeft + (currentX + c) * _cellSize;
            final by = _boardTop + (gy + r) * _cellSize;
            if (by >= _boardTop) {
              _drawGhostBlock(canvas, bx, by, _cellSize, currentPieceType);
            }
          }
        }
      }

      // 4. Draw Currently Falling Piece
      for (int r = 0; r < currentPiece.length; r++) {
        for (int c = 0; c < currentPiece[r].length; c++) {
          if (currentPiece[r][c] != 0) {
            final bx = _boardLeft + (currentX + c) * _cellSize;
            final by = _boardTop + (currentY + r) * _cellSize;
            if (by >= _boardTop) {
              _drawBlock(canvas, bx, by, _cellSize, currentPieceType);
            }
          }
        }
      }
    }

    // 5. Draw Side Panels (Hold and Next)
    _renderSidePanels(canvas);

    // 6. Draw Touch Control Buttons for Mobile / Web Clicking
    _renderTouchControls(canvas);

    // 7. Draw Visual Overlays (GameOver, Resurrect, Sword Effect)
    _renderOverlays(canvas);
  }

  void _drawBlock(Canvas canvas, double x, double y, double size, int type) {
    final color = _getPieceColor(type);
    final rect = Rect.fromLTWH(x + 1, y + 1, size - 2, size - 2);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));
    canvas.drawRRect(rrect, Paint()..color = color);

    // Top-left bevel highlight
    final highlightPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawPath(
      Path()
        ..moveTo(x + 2, y + size - 2)
        ..lineTo(x + 2, y + 2)
        ..lineTo(x + size - 2, y + 2),
      highlightPaint,
    );

    // Bottom-right bevel shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawPath(
      Path()
        ..moveTo(x + 2, y + size - 2)
        ..lineTo(x + size - 2, y + size - 2)
        ..lineTo(x + size - 2, y + 2),
      shadowPaint,
    );
  }

  void _drawGhostBlock(Canvas canvas, double x, double y, double size, int type) {
    final color = _getPieceColor(type).withOpacity(0.2);
    final rect = Rect.fromLTWH(x + 1, y + 1, size - 2, size - 2);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));
    
    // Draw semi-transparent filled block with dotted outline
    canvas.drawRRect(rrect, Paint()..color = color);
    
    final borderPaint = Paint()
      ..color = _getPieceColor(type).withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(rrect, borderPaint);
  }

  void _renderSidePanels(Canvas canvas) {
    final panelBgPaint = Paint()..color = const Color(0xFF13192B);
    final panelBorderPaint = Paint()
      ..color = const Color(0xFF1E294B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // LEFT PANEL: HOLD
    final holdPanelWidth = _boardLeft - 30;
    if (holdPanelWidth > 60) {
      final holdPanelRect = Rect.fromLTWH(15, _boardTop, holdPanelWidth, holdPanelWidth * 0.9);
      canvas.drawRRect(RRect.fromRectAndRadius(holdPanelRect, const Radius.circular(8)), panelBgPaint);
      canvas.drawRRect(RRect.fromRectAndRadius(holdPanelRect, const Radius.circular(8)), panelBorderPaint);
      
      _titleRenderer.render(canvas, 'HOLD', Vector2(25, _boardTop + 8));

      if (heldPiece != null) {
        final previewCellSize = math.min(15.0, (holdPanelWidth - 20) / 4);
        final px = 15 + (holdPanelWidth - heldPiece![0].length * previewCellSize) / 2;
        final py = _boardTop + 30 + (holdPanelWidth * 0.9 - 30 - heldPiece!.length * previewCellSize) / 2;

        for (int r = 0; r < heldPiece!.length; r++) {
          for (int c = 0; c < heldPiece![r].length; c++) {
            if (heldPiece![r][c] != 0) {
              _drawBlock(canvas, px + c * previewCellSize, py + r * previewCellSize, previewCellSize, heldPieceType!);
            }
          }
        }
      }
    }

    // RIGHT PANEL: NEXT
    final rightPanelX = _boardLeft + _boardWidth + 15;
    final rightPanelWidth = size.x - rightPanelX - 15;
    if (rightPanelWidth > 60) {
      final nextPanelRect = Rect.fromLTWH(rightPanelX, _boardTop, rightPanelWidth, rightPanelWidth * 0.9);
      canvas.drawRRect(RRect.fromRectAndRadius(nextPanelRect, const Radius.circular(8)), panelBgPaint);
      canvas.drawRRect(RRect.fromRectAndRadius(nextPanelRect, const Radius.circular(8)), panelBorderPaint);
      
      _titleRenderer.render(canvas, 'NEXT', Vector2(rightPanelX + 10, _boardTop + 8));

      final previewCellSize = math.min(15.0, (rightPanelWidth - 20) / 4);
      final px = rightPanelX + (rightPanelWidth - nextPiece[0].length * previewCellSize) / 2;
      final py = _boardTop + 30 + (rightPanelWidth * 0.9 - 30 - nextPiece.length * previewCellSize) / 2;

      for (int r = 0; r < nextPiece.length; r++) {
        for (int c = 0; c < nextPiece[r].length; c++) {
          if (nextPiece[r][c] != 0) {
            _drawBlock(canvas, px + c * previewCellSize, py + r * previewCellSize, previewCellSize, nextPieceType);
          }
        }
      }

      // HUD Stats panel below NEXT
      final hudTop = _boardTop + rightPanelWidth * 0.9 + 15;
      final hudRect = Rect.fromLTWH(rightPanelX, hudTop, rightPanelWidth, size.y - hudTop - 20);
      canvas.drawRRect(RRect.fromRectAndRadius(hudRect, const Radius.circular(8)), panelBgPaint);
      canvas.drawRRect(RRect.fromRectAndRadius(hudRect, const Radius.circular(8)), panelBorderPaint);

      final double statsLeft = rightPanelX + 10;
      _titleRenderer.render(canvas, 'STATS', Vector2(statsLeft, hudTop + 8));
      
      _textRenderer.render(canvas, 'Score: $score', Vector2(statsLeft, hudTop + 35));
      _textRenderer.render(canvas, 'High: $highScore', Vector2(statsLeft, hudTop + 55));
      _textRenderer.render(canvas, 'Level: $level', Vector2(statsLeft, hudTop + 75));
      _textRenderer.render(canvas, 'Lines: $lifetimeCoins', Vector2(statsLeft, hudTop + 95));
      
      final heartStr = '♥' * math.max(0, lives - 1);
      _textRenderer.render(canvas, 'Lives: $heartStr ($lives)', Vector2(statsLeft, hudTop + 115));
      
      if (swordCharges > 0) {
        _textRenderer.render(canvas, 'Sword: ×$swordCharges', Vector2(statsLeft, hudTop + 135));
      }
    }
  }

  void _renderTouchControls(Canvas canvas) {
    // Touch controls coordinates
    final leftPanelCenterX = _boardLeft / 2;
    if (leftPanelCenterX <= 30) return; // don't draw on extremely tiny viewport sizes

    final rightPanelCenterX = _boardLeft + _boardWidth + (size.x - _boardLeft - _boardWidth) / 2;
    final r = math.max(20.0, _cellSize * 1.1);

    final leftButtonsY = size.y - _cellSize * 4.5;
    final rotateButtonY = size.y - _cellSize * 2.0;
    final rightButtonsY = size.y - _cellSize * 4.5;
    final swordButtonY = size.y - _cellSize * 2.0;

    final leftButtonX = leftPanelCenterX - _cellSize * 1.3;
    final rightButtonX = leftPanelCenterX + _cellSize * 1.3;
    final rotateButtonX = leftPanelCenterX;

    final softDropButtonX = rightPanelCenterX - _cellSize * 1.3;
    final hardDropButtonX = rightPanelCenterX + _cellSize * 1.3;
    final swordButtonX = rightPanelCenterX;

    final btnPaint = Paint()
      ..color = const Color(0x333DBEFF)
      ..style = PaintingStyle.fill;
    final btnBorderPaint = Paint()
      ..color = const Color(0x883DBEFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    void drawBtn(double cx, double cy, String text) {
      canvas.drawCircle(Offset(cx, cy), r, btnPaint);
      canvas.drawCircle(Offset(cx, cy), r, btnBorderPaint);

      final textSpan = TextSpan(
        style: TextStyle(
          color: Colors.white.withOpacity(0.8),
          fontSize: r * 0.9,
          fontWeight: FontWeight.bold,
        ),
        text: text,
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(cx - textPainter.width / 2, cy - textPainter.height / 2),
      );
    }

    // Left controls
    drawBtn(leftButtonX, leftButtonsY, '◀');
    drawBtn(rightButtonX, leftButtonsY, '▶');
    drawBtn(rotateButtonX, rotateButtonY, '↻');

    // Right controls
    drawBtn(softDropButtonX, rightButtonsY, '▼');
    drawBtn(hardDropButtonX, rightButtonsY, '⤓');

    if (swordCharges > 0) {
      final swordBtnPaint = Paint()
        ..color = const Color(0x33FFC857)
        ..style = PaintingStyle.fill;
      final swordBtnBorderPaint = Paint()
        ..color = const Color(0x88FFC857)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawCircle(Offset(swordButtonX, swordButtonY), r, swordBtnPaint);
      canvas.drawCircle(Offset(swordButtonX, swordButtonY), r, swordBtnBorderPaint);

      final textSpan = TextSpan(
        style: TextStyle(
          color: const Color(0xFFFFC857),
          fontSize: r * 0.9,
          fontWeight: FontWeight.bold,
        ),
        text: '⚔',
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(swordButtonX - textPainter.width / 2, swordButtonY - textPainter.height / 2),
      );
    } else {
      // Draw Hold button instead on bottom right if sword empty
      drawBtn(swordButtonX, swordButtonY, '⟳');
    }
  }

  void _renderOverlays(Canvas canvas) {
    // 1. Game Over Overlay
    if (gameOver) {
      final overlayRect = Rect.fromLTWH(0, 0, size.x, size.y);
      canvas.drawRect(overlayRect, Paint()..color = Colors.black.withOpacity(0.75));

      final bigTextRenderer = TextPaint(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          fontFamily: 'Courier New',
        ),
      );

      bigTextRenderer.render(
        canvas,
        'GAME OVER',
        Vector2(size.x / 2, size.y / 2 - 50),
        anchor: Anchor.center,
      );

      _textRenderer.render(
        canvas,
        'Score $score · Level $level · Lines $lifetimeCoins',
        Vector2(size.x / 2, size.y / 2),
        anchor: Anchor.center,
      );

      _textRenderer.render(
        canvas,
        'Tap / Space / Enter to restart',
        Vector2(size.x / 2, size.y / 2 + 40),
        anchor: Anchor.center,
      );
      return;
    }

    // 2. Extra Life/Resurrect Banner
    if (_showResurrectBanner) {
      final bannerBgPaint = Paint()..color = const Color(0xCC00E676);
      canvas.drawRect(Rect.fromLTWH(0, size.y / 2 - 30, size.x, 60), bannerBgPaint);

      final bannerTextRenderer = TextPaint(
        style: const TextStyle(
          color: Colors.black,
          fontSize: 20,
          fontWeight: FontWeight.w900,
          fontFamily: 'Courier New',
        ),
      );
      bannerTextRenderer.render(
        canvas,
        'RESURRECTED! EXTRA LIFE ACTIVATED',
        Vector2(size.x / 2, size.y / 2),
        anchor: Anchor.center,
      );
    }

    // 3. Sword Flash Clear Effect
    if (_showSwordEffect) {
      final swordFlashPaint = Paint()
        ..color = const Color(0x77FFD600)
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTWH(
          _boardLeft,
          _boardTop + (rows - 3) * _cellSize,
          _boardWidth,
          3 * _cellSize,
        ),
        swordFlashPaint,
      );
    }
  }

  Color _getPieceColor(int type) {
    return switch (type) {
      1 => const Color(0xFF00E5FF), // Cyan (I)
      2 => const Color(0xFFFFD600), // Yellow (O)
      3 => const Color(0xFFD500F9), // Purple (T)
      4 => const Color(0xFF00E676), // Green (S)
      5 => const Color(0xFFFF1744), // Red (Z)
      6 => const Color(0xFF2979FF), // Blue (J)
      7 => const Color(0xFFFF9100), // Orange (L)
      8 => const Color(0xFF757575), // Grey (Garbage)
      _ => const Color(0xFF1E293B),
    };
  }

  // ---- Tap and Keyboard Inputs ----------------------------------------------

  @override
  void onTapDown(TapDownEvent event) {
    if (gameOver) {
      _restart();
      return;
    }

    final pos = event.localPosition;
    final leftPanelCenterX = _boardLeft / 2;
    if (leftPanelCenterX <= 30) return;

    final rightPanelCenterX = _boardLeft + _boardWidth + (size.x - _boardLeft - _boardWidth) / 2;
    final r = math.max(20.0, _cellSize * 1.1);

    final leftButtonsY = size.y - _cellSize * 4.5;
    final rotateButtonY = size.y - _cellSize * 2.0;
    final rightButtonsY = size.y - _cellSize * 4.5;
    final swordButtonY = size.y - _cellSize * 2.0;

    final leftButtonX = leftPanelCenterX - _cellSize * 1.3;
    final rightButtonX = leftPanelCenterX + _cellSize * 1.3;
    final rotateButtonX = leftPanelCenterX;

    final softDropButtonX = rightPanelCenterX - _cellSize * 1.3;
    final hardDropButtonX = rightPanelCenterX + _cellSize * 1.3;
    final swordButtonX = rightPanelCenterX;

    bool checkBtn(double cx, double cy) {
      final dx = pos.x - cx;
      final dy = pos.y - cy;
      return dx * dx + dy * dy <= r * r;
    }

    if (checkBtn(leftButtonX, leftButtonsY)) {
      _moveLeft();
    } else if (checkBtn(rightButtonX, leftButtonsY)) {
      _moveRight();
    } else if (checkBtn(rotateButtonX, rotateButtonY)) {
      _rotatePiece();
    } else if (checkBtn(softDropButtonX, rightButtonsY)) {
      _softDrop();
    } else if (checkBtn(hardDropButtonX, rightButtonsY)) {
      _hardDrop();
    } else if (checkBtn(swordButtonX, swordButtonY)) {
      if (swordCharges > 0) {
        _useSword();
      } else {
        _holdPiece();
      }
    }
  }

  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (gameOver) {
      if (event is KeyDownEvent &&
          (keysPressed.contains(LogicalKeyboardKey.enter) ||
              keysPressed.contains(LogicalKeyboardKey.keyR) ||
              keysPressed.contains(LogicalKeyboardKey.space))) {
        _restart();
      }
      return KeyEventResult.handled;
    }

    if (event is KeyDownEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyA) {
        _moveLeft();
      } else if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.keyD) {
        _moveRight();
      } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyW) {
        _rotatePiece();
      } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.keyS) {
        _softDrop();
      } else if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.enter) {
        _hardDrop();
      } else if (key == LogicalKeyboardKey.keyC || key == LogicalKeyboardKey.shiftLeft || key == LogicalKeyboardKey.shiftRight) {
        _holdPiece();
      } else if (key == LogicalKeyboardKey.keyE || key == LogicalKeyboardKey.keyF) {
        _useSword();
      }
    }
    return KeyEventResult.handled;
  }
}
