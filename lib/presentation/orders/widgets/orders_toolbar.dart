import 'package:flutter/material.dart';

class OrdersToolbar extends StatefulWidget {
  final String search;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onOpenColumns;
  final VoidCallback onExport;
  final List<Widget> actions;

  const OrdersToolbar({
    super.key,
    required this.search,
    required this.onSearchChanged,
    required this.onOpenColumns,
    required this.onExport,
    required this.actions,
  });

  @override
  State<OrdersToolbar> createState() => _OrdersToolbarState();
}

class _OrdersToolbarState extends State<OrdersToolbar> {
  late final TextEditingController _controller;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.search);
    _focus = FocusNode();
  }

  @override
  void didUpdateWidget(covariant OrdersToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.search != widget.search &&
        widget.search != _controller.text) {
      final sel = _controller.selection;
      _controller.text = widget.search;

      final offset = sel.baseOffset.clamp(0, _controller.text.length);
      _controller.selection = TextSelection.collapsed(offset: offset);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Directionality(
            textDirection: TextDirection.ltr, // ✅ يمنع الانعكاس
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              textDirection: TextDirection.ltr, // ✅
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search item code / name / barcode...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onChanged: widget.onSearchChanged, // ✅ يرسل للـ Bloc
            ),
          ),
        ),
        const SizedBox(width: 10),

        // Columns
        OutlinedButton.icon(
          onPressed: widget.onOpenColumns,
          icon: const Icon(Icons.view_column_outlined),
          label: const Text('Columns'),
        ),
        const SizedBox(width: 10),

        // Export
        FilledButton.icon(
          onPressed: widget.onExport,
          icon: const Icon(Icons.download),
          label: const Text('Export'),
        ),

        ...widget.actions,
      ],
    );
  }
}
