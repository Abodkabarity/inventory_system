import 'package:flutter/material.dart';

import 'additional_request_tile.dart';

class QueuePanel extends StatelessWidget {
  final List branches;
  final List requests;

  const QueuePanel({super.key, required this.branches, required this.requests});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                "Additional Requests",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...requests.map((r) => AdditionalRequestTile(request: r)),
            ],
          ),
        ),
      ],
    );
  }
}
