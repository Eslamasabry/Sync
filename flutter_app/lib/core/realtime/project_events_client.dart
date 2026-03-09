import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class ProjectEventsClient {
  ProjectEventsClient({
    required this.baseWsUrl,
    this.authToken = '',
    this.initialReconnectDelay = const Duration(seconds: 1),
    this.maxReconnectDelay = const Duration(seconds: 8),
  });

  final String baseWsUrl;
  final String authToken;
  final Duration initialReconnectDelay;
  final Duration maxReconnectDelay;

  Stream<Map<String, dynamic>> connect(String projectId) {
    late final StreamController<Map<String, dynamic>> controller;
    WebSocketChannel? channel;
    StreamSubscription<Object?>? subscription;
    Future<void>? runLoop;
    var isClosed = false;

    Future<void> closeChannel() async {
      await subscription?.cancel();
      subscription = null;
      await channel?.sink.close();
      channel = null;
    }

    Duration reconnectDelay(int attempt) {
      if (attempt <= 0) {
        return Duration.zero;
      }

      final multiplier = 1 << (attempt - 1);
      final milliseconds = initialReconnectDelay.inMilliseconds * multiplier;
      final cappedMilliseconds = milliseconds > maxReconnectDelay.inMilliseconds
          ? maxReconnectDelay.inMilliseconds
          : milliseconds;
      return Duration(milliseconds: cappedMilliseconds);
    }

    Map<String, dynamic>? decodeEvent(Object? event) {
      try {
        if (event is String) {
          final decoded = jsonDecode(event);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
          if (decoded is Map) {
            return decoded.cast<String, dynamic>();
          }
          return null;
        }

        if (event is Map<String, dynamic>) {
          return event;
        }
        if (event is Map) {
          return event.cast<String, dynamic>();
        }
      } on FormatException {
        return null;
      }

      return null;
    }

    Future<void> runConnectionLoop() async {
      var reconnectAttempt = 0;

      while (!isClosed) {
        if (reconnectAttempt > 0) {
          await Future<void>.delayed(reconnectDelay(reconnectAttempt));
          if (isClosed) {
            break;
          }
        }

        final disconnected = Completer<void>();
        var receivedMessage = false;

        try {
          channel = WebSocketChannel.connect(projectUri(projectId));
          subscription = channel!.stream.listen(
            (event) {
              final decoded = decodeEvent(event);
              if (decoded == null || controller.isClosed) {
                return;
              }

              receivedMessage = true;
              reconnectAttempt = 0;
              controller.add(decoded);
            },
            onError: (_) {
              if (!disconnected.isCompleted) {
                disconnected.complete();
              }
            },
            onDone: () {
              if (!disconnected.isCompleted) {
                disconnected.complete();
              }
            },
            cancelOnError: true,
          );

          await disconnected.future;
        } catch (_) {
          // Swallow transport errors and retry with backoff.
        } finally {
          await closeChannel();
        }

        if (!receivedMessage) {
          reconnectAttempt += 1;
        }
      }
    }

    controller = StreamController<Map<String, dynamic>>(
      onListen: () {
        runLoop = runConnectionLoop();
      },
      onCancel: () async {
        isClosed = true;
        await closeChannel();
        await runLoop;
      },
    );
    return controller.stream;
  }

  Uri projectUri(String projectId) {
    final uri = Uri.parse('$baseWsUrl/ws/projects/$projectId');
    if (authToken.trim().isEmpty) {
      return uri;
    }
    return uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        'access_token': authToken.trim(),
      },
    );
  }
}
