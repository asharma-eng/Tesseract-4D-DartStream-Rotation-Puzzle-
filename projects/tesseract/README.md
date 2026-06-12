# Tesseract 4D // DartStream Rotation Puzzle Game

A full-stack, real-time developer puzzle game built on top of the **DartStream** framework using the **Standard Engine** and **Shelf Middleware** extension layers.

---

## 🌌 Project Overview
**Tesseract 4D** is an interactive spatial lock-matching puzzle. The objective is to align a 4-dimensional hypercube (tesseract) wireframe model with a target dimensional blueprint using rotation coordinates on six different planes:
- **3D Rotations**: XY, XZ, and YZ planes.
- **4D Rotations**: XW, YW, and ZW planes (rotating along the W-depth dimension, creating a folding "inside-out" perspective projection).

The application demonstrates real-time Server-Sent Events (SSE) broadcasting architectures using DartStream telemetry feeds and Shelf route handlers.

---

## 🛠️ Key Features
- **4D Perspective Projection**: Implements full 4D matrix rotation equations and renders perspective projection calculations directly on HTML5 Canvas.
- **Reactive Telemetry Event Feed**: Uses DartStream core streams to pipe and broadcast live client events (rotations, highscores, level wins) over an active Server-Sent Events (SSE) feed (`/api/stream`).
- **Scripted Game Master Chat**: Connects to an automated assistant route (`/api/chat`) that answers questions about 4D coordinate geometries and provides clues.
- **Dynamic Configuration Flags**: Supports synchronizing dynamic settings (W-axis slider toggles, reference blueprints, hypercolor modes, and alignment difficulty) in memory.
- **Cyberpunk Dark Theme**: Modern glassmorphic console style utilizing Google Fonts (Inter, JetBrains Mono) and CSS gradients.

---

## 📂 Project Structure
```text
tesseract/
├── bin/
│   └── main.dart          # Shelf Backend server, SSE hub, chat and telemetry endpoints
├── config.yaml            # Active project features configuration
├── dartstream.yaml        # Project metadata
├── pubspec.yaml           # Dependencies and local package overrides
├── web/
│   ├── index.html         # Console UI layout
│   ├── style.css          # Glassmorphic cyberpunk styling
│   └── app.js             # 4D rotation math, SSE client, Canvas rendering loop
└── test/                  # Test suites
```

---

## 🔌 API Documentation

| Endpoint | Method | Description |
|---|---|---|
| `/` | `GET` | Serves the main Tesseract 4D interactive web console |
| `/api/status` | `GET` | Returns general server health, engine name, and level high scores |
| `/api/stream` | `GET` | Real-time Server-Sent Events (SSE) stream (broadcasts telemetry packets) |
| `/api/game/telemetry` | `POST` | Receives client logs and notifies all connected SSE channels |
| `/api/chat` | `POST` | Scripted Game Master chat responder |
| `/api/features` | `GET` / `POST` | Fetches or updates dynamic feature flags |

---

## 🚀 Getting Started

### 1. Authenticate CLI (Optional)
To associate your local workspace activity and build telemetry with your company's DartStream account, run the login command:
```bash
dartstream login --token DARTSTREAM_TOKEN_PLACEHOLDER
```

### 2. Install Dependencies
Ensure you have the Dart SDK installed. Run the following command in the project folder to retrieve dependencies:
```bash
dart pub get
```

### 2. Run the Application
Start the Tesseract server locally:
```bash
dart run bin/main.dart
```

### 3. Open in Browser
Visit the active web dashboard in your browser:
- **Game URL**: [http://localhost:8080/](http://localhost:8080/)
- **Live Stream Logs**: [http://localhost:8080/api/stream](http://localhost:8080/api/stream)

---

## 🎮 How to Play
1. Look at the smaller **Target Dimension Blueprint** on the right side.
2. Drag the **Sliders** on the left to rotate the larger central tesseract.
   - Adjust **XY, XZ, and YZ** to spin the shape along standard 3D dimensions.
   - Adjust **XW, YW, and ZW** to fold the shape in the 4th dimension (changing spacing between the inner and outer hypercube structures).
3. Align the vertices of the main structure to match the blueprint.
4. When the **Alignment Match** reaches the success threshold (95% standard or 98% hardcore mode), the lock will decrypt and unlock the **Next Level**!
