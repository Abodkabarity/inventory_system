import 'package:flutter/material.dart';

import '../../../domain/entities/additional_request_group.dart';
import 'additional_request_tile.dart';

class AdditionalPanel extends StatefulWidget {
  final List<AdditionalRequestGroup> requests;

  const AdditionalPanel({super.key, required this.requests});

  @override
  State<AdditionalPanel> createState() => _AdditionalPanelState();
}

class _AdditionalPanelState extends State<AdditionalPanel> {
  @override
  Widget build(BuildContext context) {
    List<AdditionalRequestGroup> list = [...widget.requests];

    /// SORT
    list.sort((a, b) {
      if (a.done == b.done) {
        return b.createdAt.compareTo(a.createdAt);
      }
      return a.done ? 1 : -1;
    });

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            "Additional Requests",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),

        const Divider(),

        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, i) {
              return AdditionalRequestTile(request: list[i]);
            },
          ),
        ),
      ],
    );
  }
}
