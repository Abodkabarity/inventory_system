import 'package:flutter/material.dart';

class HistoryFilterBar extends StatelessWidget {
  final DateTime? from;
  final DateTime? to;

  const HistoryFilterBar({super.key, required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Text("History"),
          const SizedBox(width: 12),
          OutlinedButton(onPressed: () {}, child: const Text("From")),
          const SizedBox(width: 10),
          OutlinedButton(onPressed: () {}, child: const Text("To")),
        ],
      ),
    );
  }
}
