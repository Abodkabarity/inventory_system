import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/utils/store_branch_identity_registry.dart';

// Headless report bridge: the Python analyst uses exactly the app's registry,
// including exportValue, rather than maintaining a second formatting rule.
void main() {
  test('stock movement report uses authoritative registry labels', () {
    const input = String.fromEnvironment('BRANCH_LABEL_INPUT');
    const output = String.fromEnvironment('BRANCH_LABEL_OUTPUT');
    if (input.isEmpty || output.isEmpty) return;
    final raw = jsonDecode(File(input).readAsStringSync()) as Map<String, dynamic>;
    final source = <String, String>{
      for (final e in raw.entries)
        e.key.trim().toUpperCase(): (e.value ?? '').toString().trim(),
    };
    StoreBranchIdentityRegistry.groups.value = source;
    final labels = <String, String>{};
    for (final name in raw.keys) {
      final display = StoreBranchIdentityRegistry.displayName(name);
      expect(StoreBranchIdentityRegistry.exportValue('branch_name', name), display);
      expect(StoreBranchIdentityRegistry.displayName(display), display);
      labels[name] = display;
    }
    expect(StoreBranchIdentityRegistry.displayName('Example', {'EXAMPLE':'71'}), '71 Example');
    expect(StoreBranchIdentityRegistry.displayName('Other', {'OTHER':'APG'}), 'Other');
    File(output).writeAsStringSync(jsonEncode(labels));
  });
}
