import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/state/agent_providers.dart';
import 'package:rikai_mobile/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('selected Agent provider is persisted across containers', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();

    ProviderContainer container() => ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );

    final first = container();
    addTearDown(first.dispose);
    expect(first.read(selectedAgentProviderProvider), isNull);

    first.read(selectedAgentProviderProvider.notifier).select('provider-b');
    expect(first.read(selectedAgentProviderProvider), 'provider-b');

    final second = container();
    addTearDown(second.dispose);
    expect(second.read(selectedAgentProviderProvider), 'provider-b');

    second.read(selectedAgentProviderProvider.notifier).select(null);
    expect(preferences.getString('agent_selected_provider_id'), isNull);
  });
}
