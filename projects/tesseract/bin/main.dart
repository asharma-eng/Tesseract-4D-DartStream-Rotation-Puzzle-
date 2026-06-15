import 'dart:io';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:tesseract/tesseract.dart';

void main() async {
  print('🎮 Starting Tesseract 4D Game Server...');

  // Create the server with SaaS integrations enabled
  final server = createServer();

  // Start the Shelf HTTP server listener
  final handler = server.handler;
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  await shelf_io.serve(handler, 'localhost', port);

  print('\n✅ Tesseract 4D Server running at http://localhost:8080');
}
