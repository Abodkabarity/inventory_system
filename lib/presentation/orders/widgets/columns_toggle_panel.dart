import 'package:flutter/material.dart';

import 'toggle_item.dart';

class ColumnsTogglePanel extends StatelessWidget {
  final List<ToggleItem> items;
  final Set<String> selectedKeys;
  final void Function(String key, bool visible) onToggle;
  final VoidCallback onReset;

  const ColumnsTogglePanel({
    super.key,
    required this.items,
    required this.selectedKeys,
    required this.onToggle,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                const Text(
                  'Columns',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                TextButton(onPressed: onReset, child: const Text('Reset')),
              ],
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final it = items[i];
                  final isOn = selectedKeys.contains(it.key);
                  return SwitchListTile(
                    value: isOn,
                    title: Text(it.title),
                    onChanged: (v) => onToggle(it.key, v),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
