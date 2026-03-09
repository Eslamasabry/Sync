import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/core/config/app_config.dart';
import 'package:sync_flutter/core/realtime/project_events_client.dart';
import 'package:sync_flutter/features/reader/state/reader_project_provider.dart';

String _wsBaseUrlFromApiBaseUrl(String apiBaseUrl) {
  if (apiBaseUrl.startsWith('https://')) {
    return apiBaseUrl.replaceFirst('https://', 'wss://');
  }
  if (apiBaseUrl.startsWith('http://')) {
    return apiBaseUrl.replaceFirst('http://', 'ws://');
  }
  return apiBaseUrl;
}

final projectEventsClientProvider = Provider<ProjectEventsClient>(
  (ref) => ProjectEventsClient(
    baseWsUrl: _wsBaseUrlFromApiBaseUrl(defaultApiBaseUrl),
    authToken: defaultApiAuthToken,
  ),
);

final projectEventsProvider = StreamProvider.autoDispose<Map<String, dynamic>>((
  ref,
) {
  final projectId = ref.watch(projectIdProvider);
  final client = ref.watch(projectEventsClientProvider);
  return _sanitizeProjectEvents(client.connect(projectId));
});

final latestProjectEventProvider =
    NotifierProvider.autoDispose<
      LatestProjectEventController,
      Map<String, dynamic>?
    >(LatestProjectEventController.new);

class LatestProjectEventController extends Notifier<Map<String, dynamic>?> {
  @override
  Map<String, dynamic>? build() => null;

  void setEvent(Map<String, dynamic> event) {
    if (!_isValidProjectEvent(event)) {
      return;
    }

    final current = state;
    if (current != null) {
      if (_eventSignature(current) == _eventSignature(event)) {
        return;
      }

      if (_isStaleReplacement(current, event)) {
        return;
      }
    }

    state = event;
  }
}

Stream<Map<String, dynamic>> _sanitizeProjectEvents(
  Stream<Map<String, dynamic>> source,
) async* {
  String? previousSignature;

  await for (final event in source) {
    if (!_isValidProjectEvent(event)) {
      continue;
    }

    final signature = _eventSignature(event);
    if (signature == previousSignature) {
      continue;
    }

    previousSignature = signature;
    yield event;
  }
}

bool _isValidProjectEvent(Map<String, dynamic> event) {
  final type = event['type'];
  final timestamp = event['timestamp'];
  final payload = event['payload'];
  return type is String &&
      type.isNotEmpty &&
      timestamp is String &&
      DateTime.tryParse(timestamp) != null &&
      payload is Map;
}

String _eventSignature(Map<String, dynamic> event) {
  final jobId = event['job_id']?.toString() ?? '';
  final type = event['type']?.toString() ?? '';
  final timestamp = event['timestamp']?.toString() ?? '';
  return '$jobId|$type|$timestamp';
}

bool _isStaleReplacement(
  Map<String, dynamic> current,
  Map<String, dynamic> incoming,
) {
  final currentJobId = current['job_id']?.toString();
  final incomingJobId = incoming['job_id']?.toString();
  if (currentJobId == null ||
      incomingJobId == null ||
      currentJobId != incomingJobId) {
    return false;
  }

  if (_isTerminalJobEvent(current) && !_isTerminalJobEvent(incoming)) {
    return true;
  }

  final currentTimestamp = DateTime.tryParse(current['timestamp'] as String);
  final incomingTimestamp = DateTime.tryParse(incoming['timestamp'] as String);
  if (currentTimestamp == null || incomingTimestamp == null) {
    return false;
  }

  return incomingTimestamp.isBefore(currentTimestamp);
}

bool _isTerminalJobEvent(Map<String, dynamic> event) {
  switch (event['type']) {
    case 'job.completed':
    case 'job.failed':
    case 'job.cancelled':
      return true;
  }
  return false;
}
