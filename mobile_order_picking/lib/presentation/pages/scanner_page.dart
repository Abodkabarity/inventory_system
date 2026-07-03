import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/app_theme.dart';
import '../../domain/entities.dart';

class ScannerPage extends StatefulWidget {
  final MobileOrderItem item;

  const ScannerPage({super.key, required this.item});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final controller = MobileScannerController();
  bool returned = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan barcode'),
        actions: [
          IconButton(
            onPressed: controller.toggleTorch,
            icon: const Icon(Icons.flashlight_on),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: (capture) {
              if (returned) return;
              String? value;
              for (final barcode in capture.barcodes) {
                final raw = barcode.rawValue;
                if (raw != null && raw.trim().isNotEmpty) {
                  value = raw;
                  break;
                }
              }
              if (value == null) return;
              returned = true;
              Navigator.pop(context, value);
            },
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 28,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Scan this item only',
                    style: TextStyle(
                      color: AppTheme.navy,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.item.itemName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text('Code: ${widget.item.itemCode}'),
                  Text(
                    'Barcode: ${widget.item.barcode.isEmpty ? 'not available' : widget.item.barcode}',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
