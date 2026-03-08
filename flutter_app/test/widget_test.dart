import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_flutter/app.dart';

void main() {
  testWidgets('renders reader shell and playback controls', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SyncApp()));

    expect(find.text('Sync'), findsOneWidget);
    expect(find.text('Moby-Dick'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Speed'), findsOneWidget);
  });
}
