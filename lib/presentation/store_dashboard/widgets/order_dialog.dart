import 'package:flutter/material.dart';

class OrderDialog extends StatelessWidget {
  final dynamic branch;

  const OrderDialog({super.key, required this.branch});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 900,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  branch.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),
            Expanded(child: Center(child: Text("Order table here"))),
          ],
        ),
      ),
    );
  }
}
