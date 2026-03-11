import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/additional_request_group.dart';
import 'additional_request_dialog.dart';

class AdditionalRequestTile extends StatelessWidget {
  final AdditionalRequestGroup request;

  const AdditionalRequestTile({super.key, required this.request});

  String _formatDate(DateTime date) {
    return DateFormat("yyyy-MM-dd  HH:mm").format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: ListTile(
        title: Text("${request.branchName} Additional Order"),
        subtitle: Text(
          _formatDate(request.createdAt),
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("${request.itemsCount} items"),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: request.done ? Colors.green : Colors.orange,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                request.done ? "DONE" : "PENDING",
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ],
        ),
        onTap: () {
          showDialog(
            context: context,
            builder: (_) => AdditionalRequestDialog(
              groupId: request.groupId,
              branch: request.branchName,
            ),
          );
        },
      ),
    );
  }
}
