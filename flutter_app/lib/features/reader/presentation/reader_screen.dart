import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/core/config/app_config.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings.dart';
import 'package:sync_flutter/core/config/runtime_connection_settings_controller.dart';
import 'package:sync_flutter/core/theme/sync_theme.dart';
import 'package:sync_flutter/features/reader/data/reader_repository.dart';
import 'package:sync_flutter/features/reader/domain/reader_model.dart';
import 'package:sync_flutter/features/reader/domain/sync_artifact.dart';
import 'package:sync_flutter/features/reader/state/reader_audio_download_controller.dart';
import 'package:sync_flutter/features/reader/state/reader_playback_controller.dart';
import 'package:sync_flutter/features/reader/state/reader_events_provider.dart';
import 'package:sync_flutter/features/reader/state/reader_project_provider.dart';

class ReaderScreen extends ConsumerWidget {
  const ReaderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(readerProjectProvider);
    final bundle = project.asData?.value;
    final connectionSettings = ref.watch(runtimeConnectionSettingsProvider);
    final recentConnections = ref.watch(
      recentRuntimeConnectionSettingsProvider,
    );
    final activeSettings =
        connectionSettings.asData?.value ?? defaultConnectionSettings;
    final playback = ref.watch(readerPlaybackProvider);
    final controller = ref.read(readerPlaybackProvider.notifier);
    final latestEvent = ref.watch(latestProjectEventProvider);
    final audioDownload = ref.watch(readerAudioDownloadProvider);
    final audioActions = ref.read(readerAudioDownloadProvider.notifier);
    final palette = ReaderPalette.of(context);

    ref.listen(projectEventsProvider, (_, next) {
      final event = next.asData?.value;
      if (event == null) {
        return;
      }

      ref.read(latestProjectEventProvider.notifier).setEvent(event);
      final type = event['type'] as String?;
      if (type == 'job.completed' ||
          type == 'job.failed' ||
          type == 'job.cancelled') {
        ref.invalidate(readerProjectProvider);
      }
    });

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.92, -1.08),
            radius: 1.8,
            colors: [
              palette.accentSoft.withValues(alpha: 0.85),
              palette.backgroundBase,
              palette.backgroundElevated,
            ],
            stops: const [0, 0.3, 1],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              children: [
                _ReaderHero(
                  project: project,
                  settings: activeSettings,
                  playback: playback,
                  onToggleTheme: controller.toggleTheme,
                  onOpenConnectionSettings: () => _showConnectionSettingsSheet(
                    context,
                    activeSettings,
                    recentConnections.asData?.value ?? const [],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 1100;
                      final controlPanel = _ControlDock(
                        bundle: bundle,
                        playback: playback,
                        latestEvent: latestEvent,
                        audioDownload: audioDownload,
                        onDownload: audioActions.downloadCurrentProject,
                        onRemove: audioActions.removeCurrentProjectAudio,
                        onRefresh: () => ref.invalidate(readerProjectProvider),
                        onStartBook: controller.seekToContentStart,
                        onJumpToOutro: controller.seekToContentEnd,
                        onSeekStart: controller.beginScrub,
                        onSeekUpdate: controller.updateScrub,
                        onSeekCommit: controller.commitScrub,
                        onRewind: controller.rewind15Seconds,
                        onForward: controller.forward15Seconds,
                        onTogglePlayback: bundle == null
                            ? null
                            : () => controller.togglePlayback(
                                bundle.syncArtifact.totalDurationMs,
                              ),
                        onSetSpeed: controller.setSpeed,
                        onJumpToStart: playback.hasLeadingMatter
                            ? controller.seekToContentStart
                            : null,
                        onJumpToEnd: playback.hasTrailingMatter
                            ? controller.seekToContentEnd
                            : null,
                      );

                      if (isWide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _ReaderStage(
                                project: project,
                                playback: playback,
                                onRetry: () =>
                                    ref.invalidate(readerProjectProvider),
                                settings: activeSettings,
                                onOpenConnectionSettings: () =>
                                    _showConnectionSettingsSheet(
                                      context,
                                      activeSettings,
                                      recentConnections.asData?.value ??
                                          const [],
                                    ),
                                onTokenTap: (token) =>
                                    controller.seekTo(token.startMs),
                              ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(width: 380, child: controlPanel),
                          ],
                        );
                      }

                      final readerHeight = (constraints.maxHeight * 0.7)
                          .clamp(320.0, 560.0)
                          .toDouble();
                      final dockHeight = (constraints.maxHeight * 0.62)
                          .clamp(bundle != null ? 320.0 : 240.0, 460.0)
                          .toDouble();

                      return ListView(
                        children: [
                          SizedBox(
                            height: readerHeight,
                            child: _ReaderStage(
                              project: project,
                              playback: playback,
                              onRetry: () =>
                                  ref.invalidate(readerProjectProvider),
                              settings: activeSettings,
                              onOpenConnectionSettings: () =>
                                  _showConnectionSettingsSheet(
                                    context,
                                    activeSettings,
                                    recentConnections.asData?.value ?? const [],
                                  ),
                              onTokenTap: (token) =>
                                  controller.seekTo(token.startMs),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(height: dockHeight, child: controlPanel),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatMs(int value) {
    final duration = Duration(milliseconds: value);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  static String formatTimestamp(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }
}

Future<void> _showConnectionSettingsSheet(
  BuildContext context,
  RuntimeConnectionSettings settings,
  List<RuntimeConnectionSettings> recentConnections,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (context) => _ConnectionSettingsSheet(
      initialSettings: settings,
      recentConnections: recentConnections,
    ),
  );
}

class _ReaderHero extends StatelessWidget {
  const _ReaderHero({
    required this.project,
    required this.settings,
    required this.playback,
    required this.onToggleTheme,
    required this.onOpenConnectionSettings,
  });

  final AsyncValue<ReaderProjectBundle> project;
  final RuntimeConnectionSettings settings;
  final ReaderPlaybackState playback;
  final VoidCallback onToggleTheme;
  final VoidCallback onOpenConnectionSettings;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final theme = Theme.of(context);
    final title = project.maybeWhen(
      data: (bundle) => bundle.readerModel.title,
      orElse: () => 'Word-level audiobook sync',
    );
    final subtitle = project.when(
      data: (bundle) => bundle.source == ReaderContentSource.demoFallback
          ? 'Demo reader loaded while the backend is unavailable.'
          : 'Live reader workspace for ${bundle.projectId}.',
      loading: () => 'Connecting to ${settings.shortHost}',
      error: (_, _) =>
          'The app can start from GitHub releases and point at your own backend at runtime.',
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sync',
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: onOpenConnectionSettings,
                      icon: const Icon(Icons.settings_input_component_rounded),
                      label: const Text('Connection'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: onToggleTheme,
                      icon: Icon(
                        playback.themeMode == ThemeMode.light
                            ? Icons.nightlight_round
                            : Icons.wb_sunny_outlined,
                      ),
                      label: Text(
                        playback.themeMode == ThemeMode.light
                            ? 'Night'
                            : 'Paper',
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _DiagnosticsChip(label: 'Project ${settings.projectId}'),
                _DiagnosticsChip(label: 'Server ${settings.shortHost}'),
                _DiagnosticsChip(
                  label: settings.hasAuthToken ? 'Auth enabled' : 'Auth open',
                ),
                _DiagnosticsChip(
                  label: settings.isLocalhostTarget
                      ? 'Localhost target'
                      : settings.usesHttp
                      ? 'HTTP dev link'
                      : 'Remote host',
                ),
                _DiagnosticsChip(
                  label: playback.themeMode == ThemeMode.light
                      ? 'Paper theme'
                      : 'Night theme',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderStage extends StatelessWidget {
  const _ReaderStage({
    required this.project,
    required this.playback,
    required this.onRetry,
    required this.settings,
    required this.onOpenConnectionSettings,
    required this.onTokenTap,
  });

  final AsyncValue<ReaderProjectBundle> project;
  final ReaderPlaybackState playback;
  final VoidCallback onRetry;
  final RuntimeConnectionSettings settings;
  final VoidCallback onOpenConnectionSettings;
  final ValueChanged<SyncToken> onTokenTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: project.when(
        data: (bundle) => _ReaderLoadedView(
          bundle: bundle,
          playback: playback,
          onTokenTap: onTokenTap,
        ),
        loading: () => _ReaderLoadingView(settings: settings),
        error: (error, _) => _ReaderErrorView(
          message: error.toString(),
          settings: settings,
          onRetry: onRetry,
          onOpenConnectionSettings: onOpenConnectionSettings,
        ),
      ),
    );
  }
}

class _ControlDock extends StatelessWidget {
  const _ControlDock({
    required this.bundle,
    required this.playback,
    required this.latestEvent,
    required this.audioDownload,
    required this.onDownload,
    required this.onRemove,
    required this.onRefresh,
    required this.onStartBook,
    required this.onJumpToOutro,
    required this.onSeekStart,
    required this.onSeekUpdate,
    required this.onSeekCommit,
    required this.onRewind,
    required this.onForward,
    required this.onTogglePlayback,
    required this.onSetSpeed,
    required this.onJumpToStart,
    required this.onJumpToEnd,
  });

  final ReaderProjectBundle? bundle;
  final ReaderPlaybackState playback;
  final Map<String, dynamic>? latestEvent;
  final ReaderAudioDownloadState audioDownload;
  final Future<void> Function() onDownload;
  final Future<void> Function() onRemove;
  final VoidCallback onRefresh;
  final Future<void> Function() onStartBook;
  final Future<void> Function() onJumpToOutro;
  final void Function(double) onSeekStart;
  final void Function(double) onSeekUpdate;
  final Future<void> Function(double) onSeekCommit;
  final VoidCallback onRewind;
  final VoidCallback onForward;
  final VoidCallback? onTogglePlayback;
  final ValueChanged<double> onSetSpeed;
  final VoidCallback? onJumpToStart;
  final VoidCallback? onJumpToEnd;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final currentPositionMs = playback.displayedPositionMs;

    return Card(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reader Status',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            if (bundle != null)
              _SourceBanner(
                source: bundle!.source,
                message: bundle!.statusMessage,
                onRefresh: onRefresh,
              ),
            if (bundle != null) const SizedBox(height: 12),
            if (bundle != null && bundle!.totalAudioAssets > 0) ...[
              _AudioDownloadBanner(
                bundle: bundle!,
                downloadState: audioDownload,
                onDownload: onDownload,
                onRemove: onRemove,
              ),
              const SizedBox(height: 12),
            ],
            if (bundle != null) ...[
              _ReaderDiagnosticsBanner(bundle: bundle!, playback: playback),
              const SizedBox(height: 12),
            ],
            if (bundle != null &&
                bundle!.syncArtifact.hasLeadingMatter &&
                currentPositionMs < bundle!.syncArtifact.contentStartMs) ...[
              _ContentWindowBanner(
                syncArtifact: bundle!.syncArtifact,
                currentPositionMs: currentPositionMs,
                onStartBook: () => onStartBook(),
                onJumpToOutro: bundle!.syncArtifact.hasTrailingMatter
                    ? () => onJumpToOutro()
                    : null,
              ),
              const SizedBox(height: 12),
            ],
            if (latestEvent != null) ...[
              _JobEventBanner(event: latestEvent!),
              const SizedBox(height: 12),
            ],
            if (bundle != null) ...[
              _GapStatusBanner(
                gap: bundle!.syncArtifact.activeGapAt(currentPositionMs),
              ),
              const SizedBox(height: 12),
              _PlaybackStatusBanner(
                playback: playback,
                currentPositionMs: currentPositionMs,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                decoration: BoxDecoration(
                  color: palette.backgroundBase,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: palette.borderSubtle),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            ReaderScreen._formatMs(currentPositionMs),
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        Text(
                          ReaderScreen._formatMs(
                            bundle!.syncArtifact.totalDurationMs,
                          ),
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: palette.textMuted),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${playback.speed.toStringAsFixed(2)}x',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: palette.textMuted),
                        ),
                      ],
                    ),
                    Slider(
                      value: currentPositionMs
                          .clamp(0, bundle!.syncArtifact.totalDurationMs)
                          .toDouble(),
                      max: bundle!.syncArtifact.totalDurationMs > 0
                          ? bundle!.syncArtifact.totalDurationMs.toDouble()
                          : 1,
                      label: ReaderScreen._formatMs(currentPositionMs),
                      onChangeStart: onSeekStart,
                      onChanged: onSeekUpdate,
                      onChangeEnd: onSeekCommit,
                    ),
                    _ContentWindowRow(
                      playback: playback,
                      currentPositionMs: currentPositionMs,
                      onJumpToStart: onJumpToStart,
                      onJumpToEnd: onJumpToEnd,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        IconButton.filledTonal(
                          onPressed: onRewind,
                          icon: const Icon(Icons.replay_10_rounded),
                        ),
                        const SizedBox(width: 12),
                        IconButton.filledTonal(
                          onPressed: onForward,
                          icon: const Icon(Icons.forward_10_rounded),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: onTogglePlayback,
                            icon: Icon(
                              playback.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                            label: Text(playback.isPlaying ? 'Pause' : 'Play'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        PopupMenuButton<double>(
                          initialValue: playback.speed,
                          onSelected: onSetSpeed,
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 0.8, child: Text('0.8x')),
                            PopupMenuItem(value: 1.0, child: Text('1.0x')),
                            PopupMenuItem(value: 1.25, child: Text('1.25x')),
                            PopupMenuItem(value: 1.5, child: Text('1.5x')),
                          ],
                          child: const _SpeedChip(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConnectionSettingsSheet extends ConsumerStatefulWidget {
  const _ConnectionSettingsSheet({
    required this.initialSettings,
    required this.recentConnections,
  });

  final RuntimeConnectionSettings initialSettings;
  final List<RuntimeConnectionSettings> recentConnections;

  @override
  ConsumerState<_ConnectionSettingsSheet> createState() =>
      _ConnectionSettingsSheetState();
}

class _ConnectionSettingsSheetState
    extends ConsumerState<_ConnectionSettingsSheet> {
  late final TextEditingController _apiBaseUrlController;
  late final TextEditingController _projectIdController;
  late final TextEditingController _authTokenController;
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _apiBaseUrlController = TextEditingController(
      text: widget.initialSettings.apiBaseUrl,
    );
    _projectIdController = TextEditingController(
      text: widget.initialSettings.projectId,
    );
    _authTokenController = TextEditingController(
      text: widget.initialSettings.authToken,
    );
  }

  @override
  void dispose() {
    _apiBaseUrlController.dispose();
    _projectIdController.dispose();
    _authTokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final currentDraft = RuntimeConnectionSettings(
      apiBaseUrl: _apiBaseUrlController.text.trim(),
      projectId: _projectIdController.text.trim(),
      authToken: _authTokenController.text.trim(),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Connection Settings', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'These values stay on this device only. Point the release APK at your own server, token, and project without rebuilding.',
                style: theme.textTheme.bodyMedium,
              ),
              if (_connectionHint(currentDraft) case final hint?) ...[
                const SizedBox(height: 16),
                _ConnectionHintBanner(message: hint),
              ],
              if (widget.recentConnections.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Recent Connections', style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final recent in widget.recentConnections)
                      ActionChip(
                        label: Text(
                          '${recent.shortHost} • ${recent.normalizedProjectId}',
                        ),
                        avatar: Icon(
                          recent.hasAuthToken
                              ? Icons.lock_outline_rounded
                              : Icons.public_outlined,
                          size: 18,
                        ),
                        onPressed: () => _applyRecent(recent),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              TextFormField(
                controller: _apiBaseUrlController,
                decoration: const InputDecoration(
                  labelText: 'Backend URL',
                  hintText: 'https://your-host/v1',
                ),
                keyboardType: TextInputType.url,
                validator: (value) {
                  final candidate = value?.trim() ?? '';
                  if (candidate.isEmpty) {
                    return 'Backend URL is required.';
                  }
                  final uri = Uri.tryParse(candidate);
                  if (uri == null ||
                      !(uri.hasScheme &&
                          (uri.scheme == 'http' || uri.scheme == 'https'))) {
                    return 'Use a full http:// or https:// URL.';
                  }
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _projectIdController,
                decoration: const InputDecoration(labelText: 'Project ID'),
                validator: (value) {
                  if ((value?.trim() ?? '').isEmpty) {
                    return 'Project ID is required.';
                  }
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _authTokenController,
                decoration: const InputDecoration(
                  labelText: 'Auth Token',
                  hintText: 'Optional bearer token',
                ),
                obscureText: true,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              Text(
                'Privacy: server URL, project ID, and token stay on this device. They are never committed or uploaded by the app.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: const Icon(Icons.cloud_done_rounded),
                    label: Text(_isSaving ? 'Saving...' : 'Save and Reload'),
                  ),
                  TextButton(
                    onPressed: _isSaving ? null : _resetToDefaults,
                    child: const Text('Reset to Release Defaults'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _applyRecent(RuntimeConnectionSettings recent) {
    _apiBaseUrlController.text = recent.normalizedApiBaseUrl;
    _projectIdController.text = recent.normalizedProjectId;
    _authTokenController.text = recent.authToken;
    setState(() {});
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);
    final settings = RuntimeConnectionSettings(
      apiBaseUrl: _apiBaseUrlController.text.trim(),
      projectId: _projectIdController.text.trim(),
      authToken: _authTokenController.text.trim(),
    );
    await ref.read(runtimeConnectionSettingsProvider.notifier).save(settings);
    ref.invalidate(projectIdProvider);
    ref.invalidate(syncApiClientProvider);
    ref.invalidate(projectEventsClientProvider);
    ref.invalidate(readerRepositoryProvider);
    ref.invalidate(readerProjectProvider);
    ref.invalidate(projectEventsProvider);
    ref.invalidate(latestProjectEventProvider);
    ref.read(readerPlaybackProvider.notifier).resetForProject();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _resetToDefaults() async {
    setState(() => _isSaving = true);
    await ref.read(runtimeConnectionSettingsProvider.notifier).reset();
    ref.invalidate(projectIdProvider);
    ref.invalidate(syncApiClientProvider);
    ref.invalidate(projectEventsClientProvider);
    ref.invalidate(readerRepositoryProvider);
    ref.invalidate(readerProjectProvider);
    ref.invalidate(projectEventsProvider);
    ref.invalidate(latestProjectEventProvider);
    ref.read(readerPlaybackProvider.notifier).resetForProject();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

String? _connectionHint(RuntimeConnectionSettings settings) {
  if (settings.normalizedApiBaseUrl.isEmpty) {
    return null;
  }
  if (settings.isLocalhostTarget) {
    return 'This target uses localhost. On a physical phone, localhost points to the phone itself, not your laptop. Use your LAN or Tailscale host instead.';
  }
  if (settings.usesHttp) {
    return 'This target uses HTTP. That is fine for local development, but deployed environments should use HTTPS so WebSocket traffic upgrades to WSS.';
  }
  return null;
}

String _errorHelp(RuntimeConnectionSettings settings) {
  if (settings.isLocalhostTarget) {
    return 'If this is a physical device, replace localhost with your laptop host or Tailscale address, then retry.';
  }
  if (!settings.hasAuthToken) {
    return 'Check that the backend URL and project ID are correct. If your server is protected, add the auth token in Connection settings.';
  }
  return 'Check that the backend URL, project ID, and auth token are all correct, then retry the request.';
}

class _ReaderLoadedView extends StatelessWidget {
  const _ReaderLoadedView({
    required this.bundle,
    required this.playback,
    required this.onTokenTap,
  });

  final ReaderProjectBundle bundle;
  final ReaderPlaybackState playback;
  final ValueChanged<SyncToken> onTokenTap;

  @override
  Widget build(BuildContext context) {
    if (bundle.readerModel.sections.isEmpty) {
      final palette = ReaderPalette.of(context);
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(28, 30, 28, 30),
          decoration: BoxDecoration(
            color: palette.backgroundElevated,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: palette.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                bundle.statusMessage ?? 'Reader content is not available yet.',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                'The backend is reachable, but there is no normalized reader model to render yet. This usually means alignment is still processing or the latest artifact is incomplete.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    final syncIndex = {
      for (final token in bundle.syncArtifact.tokens)
        token.location.locationKey: token,
    };
    final activeLocationKey = _activeToken(
      bundle.syncArtifact,
      playback.displayedPositionMs,
    )?.location.locationKey;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final section in bundle.readerModel.sections) ...[
                if (section.title != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Text(
                      section.title!,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                for (final paragraph in section.paragraphs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: _ParagraphBlock(
                      section: section,
                      paragraph: paragraph,
                      activeLocationKey: activeLocationKey,
                      syncIndex: syncIndex,
                      onTokenTap: (token) {
                        if (token != null) {
                          onTokenTap(token);
                        }
                      },
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static SyncToken? _activeToken(SyncArtifact artifact, int positionMs) {
    for (final token in artifact.tokens) {
      if (positionMs >= token.startMs && positionMs < token.endMs) {
        return token;
      }
    }
    if (artifact.tokens.isNotEmpty &&
        positionMs >= artifact.tokens.last.endMs) {
      return artifact.tokens.last;
    }
    return null;
  }
}

class _ReaderLoadingView extends StatelessWidget {
  const _ReaderLoadingView({required this.settings});

  final RuntimeConnectionSettings settings;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(28, 30, 28, 30),
        decoration: BoxDecoration(
          color: palette.backgroundElevated,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: palette.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            Text(
              'Opening reader workspace',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            Text(
              'Connecting to ${settings.shortHost} for project ${settings.normalizedProjectId}.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
            ),
            if (_connectionHint(settings) case final hint?) ...[
              const SizedBox(height: 16),
              _ConnectionHintBanner(message: hint),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReaderErrorView extends StatelessWidget {
  const _ReaderErrorView({
    required this.message,
    required this.settings,
    required this.onRetry,
    required this.onOpenConnectionSettings,
  });

  final String message;
  final RuntimeConnectionSettings settings;
  final VoidCallback onRetry;
  final VoidCallback onOpenConnectionSettings;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(28, 30, 28, 30),
        decoration: BoxDecoration(
          color: palette.backgroundElevated,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: palette.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Reader failed to load',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            Text(
              'Current target: ${settings.shortHost} • ${settings.normalizedProjectId}',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: 16),
            Text(message),
            const SizedBox(height: 16),
            Text(
              _errorHelp(settings),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
            ),
            if (_connectionHint(settings) case final hint?) ...[
              const SizedBox(height: 16),
              _ConnectionHintBanner(message: hint),
            ],
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(onPressed: onRetry, child: const Text('Retry')),
                FilledButton.tonal(
                  onPressed: onOpenConnectionSettings,
                  child: const Text('Open Connection'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionHintBanner extends StatelessWidget {
  const _ConnectionHintBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.accentSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _SourceBanner extends StatelessWidget {
  const _SourceBanner({
    required this.source,
    required this.onRefresh,
    this.message,
  });

  final ReaderContentSource source;
  final VoidCallback onRefresh;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final isFallback =
        source == ReaderContentSource.demoFallback ||
        source == ReaderContentSource.offlineCache;
    final isProblem =
        source == ReaderContentSource.artifactPending ||
        source == ReaderContentSource.projectError;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isFallback
            ? palette.accentSoft
            : isProblem
            ? palette.backgroundElevated
            : palette.backgroundBase,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message ??
                  switch (source) {
                    ReaderContentSource.api => 'Backend project loaded.',
                    ReaderContentSource.offlineCache =>
                      'Cached reader artifacts loaded from this device.',
                    ReaderContentSource.artifactPending =>
                      'Backend project is available, but reader artifacts are still processing.',
                    ReaderContentSource.projectError =>
                      'Backend project loaded, but the latest reader artifacts are incomplete.',
                    ReaderContentSource.demoFallback =>
                      'Demo data loaded because the API is unavailable.',
                  },
            ),
          ),
          TextButton(onPressed: onRefresh, child: const Text('Refresh')),
        ],
      ),
    );
  }
}

class _JobEventBanner extends StatelessWidget {
  const _JobEventBanner({required this.event});

  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final type = event['type'] as String? ?? 'job.progress';
    final payload = (event['payload'] as Map<Object?, Object?>?) ?? const {};
    final stage = payload['stage'] as String? ?? 'unknown';
    final percent = payload['percent'] as int? ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.backgroundBase,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Text(
        '$type • $stage • $percent%',
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}

class _AudioDownloadBanner extends StatelessWidget {
  const _AudioDownloadBanner({
    required this.bundle,
    required this.downloadState,
    required this.onDownload,
    required this.onRemove,
  });

  final ReaderProjectBundle bundle;
  final ReaderAudioDownloadState downloadState;
  final Future<void> Function() onDownload;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final theme = Theme.of(context);
    final message = switch (downloadState.status) {
      ReaderAudioDownloadStatus.downloading =>
        'Downloading audio for offline playback...',
      ReaderAudioDownloadStatus.removing =>
        'Removing downloaded audio from this device...',
      ReaderAudioDownloadStatus.failed =>
        downloadState.message ?? 'Audio download failed.',
      _ when bundle.hasCompleteOfflineAudio =>
        'Offline audio is ready on this device.',
      _ when bundle.cachedAudioAssets > 0 =>
        'Partial offline audio: ${bundle.cachedAudioAssets} of ${bundle.totalAudioAssets} files downloaded.',
      _ =>
        'Audio will stream from the backend until you download it for offline playback.',
    };

    final trailingMessage = switch (downloadState.status) {
      ReaderAudioDownloadStatus.succeeded => downloadState.message,
      ReaderAudioDownloadStatus.failed => null,
      ReaderAudioDownloadStatus.downloading =>
        '${(downloadState.progress * 100).round()}%',
      _ => null,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.backgroundBase,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: theme.textTheme.bodyMedium),
          if (trailingMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              trailingMessage,
              style: theme.textTheme.labelMedium?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ],
          if (downloadState.status ==
              ReaderAudioDownloadStatus.downloading) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: downloadState.progress),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: downloadState.isBusy ? null : onDownload,
                child: Text(
                  bundle.cachedAudioAssets > 0 &&
                          !bundle.hasCompleteOfflineAudio
                      ? 'Download Remaining'
                      : bundle.hasCompleteOfflineAudio
                      ? 'Re-download Audio'
                      : 'Download Audio',
                ),
              ),
              if (bundle.cachedAudioAssets > 0 ||
                  bundle.hasCompleteOfflineAudio)
                TextButton(
                  onPressed: downloadState.isBusy ? null : onRemove,
                  child: const Text('Remove Local Copy'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContentWindowBanner extends StatelessWidget {
  const _ContentWindowBanner({
    required this.syncArtifact,
    required this.currentPositionMs,
    required this.onStartBook,
    this.onJumpToOutro,
  });

  final SyncArtifact syncArtifact;
  final int currentPositionMs;
  final VoidCallback onStartBook;
  final VoidCallback? onJumpToOutro;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final remainingMs = syncArtifact.contentStartMs - currentPositionMs;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.accentSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Intro detected before the book starts at '
              '${ReaderScreen._formatMs(syncArtifact.contentStartMs)}'
              ' (${ReaderScreen._formatMs(remainingMs)} away).',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          TextButton(onPressed: onStartBook, child: const Text('Start Book')),
          if (onJumpToOutro != null)
            TextButton(onPressed: onJumpToOutro, child: const Text('Outro')),
        ],
      ),
    );
  }
}

class _ReaderDiagnosticsBanner extends StatelessWidget {
  const _ReaderDiagnosticsBanner({
    required this.bundle,
    required this.playback,
  });

  final ReaderProjectBundle bundle;
  final ReaderPlaybackState playback;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.backgroundBase,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_headline(bundle, playback), style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(
            _detail(bundle, playback),
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DiagnosticsChip(label: _artifactSourceLabel(bundle.source)),
              _DiagnosticsChip(
                label:
                    'Local audio ${bundle.cachedAudioAssets}/${bundle.totalAudioAssets}',
              ),
              if (bundle.streamingAudioAssets > 0)
                _DiagnosticsChip(
                  label: 'Streaming ${bundle.streamingAudioAssets}',
                ),
              _DiagnosticsChip(
                label: playback.usesNativeAudio
                    ? 'Native audio active'
                    : 'Text timeline mode',
              ),
              if (bundle.audioCachedAt != null)
                _DiagnosticsChip(
                  label:
                      'Audio cache ${ReaderScreen.formatTimestamp(bundle.audioCachedAt!)}',
                ),
              if (bundle.cachedAt != null)
                _DiagnosticsChip(
                  label:
                      'Artifacts cache ${ReaderScreen.formatTimestamp(bundle.cachedAt!)}',
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _headline(
    ReaderProjectBundle bundle,
    ReaderPlaybackState playback,
  ) {
    return switch (bundle.playbackSourceMode(
      usesNativeAudio: playback.usesNativeAudio,
    )) {
      ReaderPlaybackSourceMode.offlineCached =>
        'Playback source: local cached audio.',
      ReaderPlaybackSourceMode.mixed =>
        'Playback source: mixed local and backend audio.',
      ReaderPlaybackSourceMode.remoteStreaming =>
        'Playback source: streaming from the backend.',
      ReaderPlaybackSourceMode.textOnly =>
        bundle.hasAnyAudio
            ? 'Playback source: text timeline only.'
            : 'Playback source: no audio source available.',
    };
  }

  static String _detail(
    ReaderProjectBundle bundle,
    ReaderPlaybackState playback,
  ) {
    final sourceMode = bundle.playbackSourceMode(
      usesNativeAudio: playback.usesNativeAudio,
    );
    if (sourceMode == ReaderPlaybackSourceMode.offlineCached) {
      return 'All project audio is downloaded on this device and native playback can run without backend access.';
    }
    if (sourceMode == ReaderPlaybackSourceMode.mixed) {
      return '${bundle.cachedAudioAssets} of ${bundle.totalAudioAssets} audio files are local. The rest will stream from the backend when needed.';
    }
    if (sourceMode == ReaderPlaybackSourceMode.remoteStreaming) {
      return 'Audio will stream from the backend. Download it on this device to enable offline playback.';
    }
    if (bundle.hasAnyAudio) {
      return playback.usesNativeAudio
          ? 'Native audio is active for the currently available files.'
          : 'This project has audio metadata, but no playable local or remote source is active right now.';
    }
    return 'Word highlighting follows the sync timeline, but there is no playable audiobook source for this project yet.';
  }

  static String _artifactSourceLabel(ReaderContentSource source) {
    return switch (source) {
      ReaderContentSource.api => 'Artifacts: live API',
      ReaderContentSource.offlineCache => 'Artifacts: offline cache',
      ReaderContentSource.artifactPending => 'Artifacts: pending',
      ReaderContentSource.projectError => 'Artifacts: incomplete',
      ReaderContentSource.demoFallback => 'Artifacts: demo data',
    };
  }
}

class _DiagnosticsChip extends StatelessWidget {
  const _DiagnosticsChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.backgroundElevated,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _PlaybackStatusBanner extends StatelessWidget {
  const _PlaybackStatusBanner({
    required this.playback,
    required this.currentPositionMs,
  });

  final ReaderPlaybackState playback;
  final int currentPositionMs;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    final phase = _phaseLabel(playback, currentPositionMs);
    final positionLabel = playback.isScrubbing ? 'Scrubbing' : 'Playback';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.backgroundBase,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$positionLabel • $phase',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          Text(
            '${playback.isPlaying ? 'Playing' : 'Paused'} • '
            '${playback.usesNativeAudio ? 'Native audio' : 'Text timeline'}',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }

  static String _phaseLabel(
    ReaderPlaybackState playback,
    int currentPositionMs,
  ) {
    if (playback.hasLeadingMatter &&
        currentPositionMs < playback.contentStartMs) {
      return 'Intro before book';
    }
    if (playback.hasTrailingMatter &&
        currentPositionMs > playback.contentEndMs) {
      return 'Outro after book';
    }
    if (playback.totalDurationMs == 0) {
      return 'No timeline';
    }
    return 'Inside book content';
  }
}

class _ContentWindowRow extends StatelessWidget {
  const _ContentWindowRow({
    required this.playback,
    required this.currentPositionMs,
    required this.onJumpToStart,
    required this.onJumpToEnd,
  });

  final ReaderPlaybackState playback;
  final int currentPositionMs;
  final VoidCallback? onJumpToStart;
  final VoidCallback? onJumpToEnd;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];

    if (onJumpToStart != null) {
      items.add(
        _WindowChip(
          label:
              'Book Start ${ReaderScreen._formatMs(playback.contentStartMs)}',
          isActive:
              currentPositionMs >= playback.contentStartMs &&
              currentPositionMs <= playback.contentEndMs,
          onTap: onJumpToStart!,
        ),
      );
    }

    if (onJumpToEnd != null) {
      items.add(
        _WindowChip(
          label: 'Book End ${ReaderScreen._formatMs(playback.contentEndMs)}',
          isActive:
              playback.hasTrailingMatter &&
              currentPositionMs >= playback.contentEndMs,
          onTap: onJumpToEnd!,
        ),
      );
    }

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(spacing: 8, runSpacing: 8, children: items),
    );
  }
}

class _WindowChip extends StatelessWidget {
  const _WindowChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return ActionChip(
      label: Text(label),
      avatar: Icon(
        isActive ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
        size: 18,
        color: isActive ? palette.accentPrimary : palette.textMuted,
      ),
      onPressed: onTap,
      side: BorderSide(color: palette.borderSubtle),
      backgroundColor: isActive ? palette.accentSoft : palette.backgroundBase,
    );
  }
}

class _GapStatusBanner extends StatelessWidget {
  const _GapStatusBanner({required this.gap});

  final SyncGap? gap;

  @override
  Widget build(BuildContext context) {
    if (gap == null) {
      return const SizedBox.shrink();
    }

    final palette = ReaderPalette.of(context);
    final message = switch (gap!.reason) {
      'audiobook_front_matter' =>
        'This portion is audiobook intro and is outside the EPUB text.',
      'audiobook_end_matter' =>
        'This portion is audiobook outro and is outside the EPUB text.',
      _ => 'Playback is in an unmatched narration span.',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.backgroundBase,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Text(message, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

class _ParagraphBlock extends StatelessWidget {
  const _ParagraphBlock({
    required this.section,
    required this.paragraph,
    required this.activeLocationKey,
    required this.syncIndex,
    required this.onTokenTap,
  });

  final ReaderSection section;
  final ReaderParagraph paragraph;
  final String? activeLocationKey;
  final Map<String, SyncToken> syncIndex;
  final ValueChanged<SyncToken?> onTokenTap;

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 12,
      children: [
        for (final token in paragraph.tokens)
          _TokenPill(
            token: token,
            syncToken:
                syncIndex['${section.id}:${paragraph.index}:${token.index}'],
            isActive:
                activeLocationKey ==
                '${section.id}:${paragraph.index}:${token.index}',
            onTap: onTokenTap,
            palette: palette,
          ),
      ],
    );
  }
}

class _TokenPill extends StatelessWidget {
  const _TokenPill({
    required this.token,
    required this.syncToken,
    required this.isActive,
    required this.onTap,
    required this.palette,
  });

  final ReaderToken token;
  final SyncToken? syncToken;
  final bool isActive;
  final ValueChanged<SyncToken?> onTap;
  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onTap(syncToken),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? palette.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? palette.accentPrimary : Colors.transparent,
          ),
        ),
        child: Text(
          token.text,
          style: textTheme.bodyLarge?.copyWith(
            color: isActive ? palette.accentPrimary : palette.textPrimary,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            decoration: isActive ? TextDecoration.underline : null,
            decorationColor: palette.accentPrimary,
          ),
        ),
      ),
    );
  }
}

class _SpeedChip extends StatelessWidget {
  const _SpeedChip();

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.accentSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Speed'),
            SizedBox(width: 6),
            Icon(Icons.tune_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}
