import 'package:flutter_test/flutter_test.dart';
import 'package:sync_flutter/core/realtime/project_events_client.dart';

void main() {
  test('project events client appends access token to websocket uri', () {
    final client = ProjectEventsClient(
      baseWsUrl: 'wss://sync.example/v1',
      authToken: 'secret-token',
    );

    final uri = client.projectUri('project-123');

    expect(
      uri.toString(),
      'wss://sync.example/v1/ws/projects/project-123?access_token=secret-token',
    );
  });

  test('project events client leaves websocket uri unchanged without auth', () {
    final client = ProjectEventsClient(baseWsUrl: 'ws://localhost:8000/v1');

    final uri = client.projectUri('project-123');

    expect(uri.toString(), 'ws://localhost:8000/v1/ws/projects/project-123');
  });
}
