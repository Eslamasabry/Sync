import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class ProjectEventsClient {
  ProjectEventsClient({required this.baseWsUrl});

  final String baseWsUrl;

  Stream<Map<String, dynamic>> connect(String projectId) {
    final channel = WebSocketChannel.connect(
      Uri.parse('$baseWsUrl/ws/projects/$projectId'),
    );

    late final StreamController<Map<String, dynamic>> controller;
    late final StreamSubscription<Object?> subscription;
    controller = StreamController<Map<String, dynamic>>(
      onListen: () {
        subscription = channel.stream.listen(
          (event) {
            controller.add(jsonDecode(event as String) as Map<String, dynamic>);
          },
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onCancel: () async {
        await subscription.cancel();
        await channel.sink.close();
      },
    );
    return controller.stream;
  }
}
