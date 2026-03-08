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
  ),
);

final projectEventsProvider = StreamProvider.autoDispose<Map<String, dynamic>>((
  ref,
) {
  final projectId = ref.watch(projectIdProvider);
  final client = ref.watch(projectEventsClientProvider);
  return client.connect(projectId);
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
    state = event;
  }
}
