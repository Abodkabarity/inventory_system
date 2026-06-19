import 'package:flutter/material.dart';

class MaxAllowedDialog extends StatelessWidget {
  final int currentQty;
  final int requestedQty;
  final int maxAllowed;
  final int finalQty;

  const MaxAllowedDialog({
    super.key,
    required this.currentQty,
    required this.requestedQty,
    required this.maxAllowed,
    required this.finalQty,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,

      title: const Text('Limited Stock', textAlign: TextAlign.center),

      content: Text(
        'Current Qty : $currentQty\n'
        'Requested Qty : $requestedQty\n'
        'Max Allowed : $maxAllowed\n'
        'Final Qty : $finalQty',
        textAlign: TextAlign.center,
      ),

      actions: [
        Row(
          children: [
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () {
                  Navigator.pop(context, 'ignore');
                },
                child: const Text(
                  'Ignore',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),

            const SizedBox(width: 10),

            Expanded(
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(context, 'add_max');
                },
                child: Text('Add Max ($maxAllowed)'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
