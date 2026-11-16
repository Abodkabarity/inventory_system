import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/daily_order_query.dart';

class InventoryDailyOrderFilter extends StatefulWidget {
  const InventoryDailyOrderFilter({
    super.key,
    required this.title,
    required this.field,
    required this.initial,
  });

  final String title;
  final DailyOrderField field;
  final DailyOrderColumnFilter? initial;

  @override
  State<InventoryDailyOrderFilter> createState() =>
      _InventoryDailyOrderFilterState();
}

class _InventoryDailyOrderFilterState extends State<InventoryDailyOrderFilter> {
  final _form = GlobalKey<FormState>();
  late final List<_FilterRule> _rules;
  late bool _matchAny;

  List<DailyOrderOperator> get _operators {
    const common = [DailyOrderOperator.equals, DailyOrderOperator.notEqual];
    const blank = [DailyOrderOperator.isEmpty, DailyOrderOperator.isNotEmpty];
    return switch (widget.field.type) {
      DailyOrderFieldType.text => [
        DailyOrderOperator.contains,
        ...common,
        DailyOrderOperator.startsWith,
        DailyOrderOperator.endsWith,
        DailyOrderOperator.doesNotContain,
        ...blank,
      ],
      DailyOrderFieldType.boolean => [...common, ...blank],
      DailyOrderFieldType.date || DailyOrderFieldType.number => [
        ...common,
        DailyOrderOperator.greaterThan,
        DailyOrderOperator.atLeast,
        DailyOrderOperator.lessThan,
        DailyOrderOperator.atMost,
        ...blank,
      ],
    };
  }

  _FilterRule _newRule() => _FilterRule(
    _operators.first,
    widget.field.type == DailyOrderFieldType.boolean ? 'true' : '',
  );

  @override
  void initState() {
    super.initState();
    _matchAny = widget.initial?.matchAny ?? false;
    _rules = [
      for (final rule in widget.initial?.rules ?? <DailyOrderRule>[])
        _FilterRule(rule.operator, rule.value),
    ];
    if (_rules.isEmpty) _rules.add(_newRule());
  }

  @override
  void dispose() {
    for (final rule in _rules) {
      rule.value.dispose();
    }
    super.dispose();
  }

  void _apply() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      DailyOrderColumnFilter([
        for (final rule in _rules)
          (operator: rule.operator, value: rule.value.text.trim()),
      ], matchAny: _matchAny),
    );
  }

  String? _validate(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return 'Enter a value';
    switch (widget.field.type) {
      case DailyOrderFieldType.number:
        if (!RegExp(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$').hasMatch(value) ||
            num.tryParse(value)?.isFinite != true) {
          return 'Enter a number';
        }
      case DailyOrderFieldType.date:
        try {
          if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
            return 'Use YYYY-MM-DD';
          }
          DateFormat('yyyy-MM-dd', 'en_US').parseStrict(value);
        } on FormatException {
          return 'Enter a valid date';
        }
      case DailyOrderFieldType.text:
      case DailyOrderFieldType.boolean:
        break;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Filter ${widget.title}'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_rules.length > 1) ...[
                DropdownButtonFormField<bool>(
                  initialValue: _matchAny,
                  decoration: const InputDecoration(
                    labelText: 'Match rules',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: false, child: Text('All rules')),
                    DropdownMenuItem(value: true, child: Text('Any rule')),
                  ],
                  onChanged: (value) => setState(() => _matchAny = value!),
                ),
                const SizedBox(height: 12),
              ],
              for (final rule in _rules) _buildRule(rule),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _rules.add(_newRule())),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add rule'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.initial != null)
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              DailyOrderColumnFilter(const [], matchAny: false),
            ),
            child: const Text('Remove filter'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _apply, child: const Text('Apply')),
      ],
    );
  }

  Widget _buildRule(_FilterRule rule) {
    return Padding(
      key: ObjectKey(rule),
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<DailyOrderOperator>(
                  initialValue: rule.operator,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Condition',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final operator in _operators)
                      DropdownMenuItem(
                        value: operator,
                        child: Text(operator.label),
                      ),
                  ],
                  onChanged: (value) => setState(() => rule.operator = value!),
                ),
              ),
              if (_rules.length > 1)
                IconButton(
                  tooltip: 'Remove rule',
                  onPressed: () {
                    setState(() => _rules.remove(rule));
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      rule.value.dispose();
                    });
                  },
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          if (rule.operator.needsValue) ...[
            const SizedBox(height: 8),
            if (widget.field.type == DailyOrderFieldType.boolean)
              DropdownButtonFormField<String>(
                initialValue: rule.value.text,
                decoration: const InputDecoration(
                  labelText: 'Value',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'true', child: Text('Yes')),
                  DropdownMenuItem(value: 'false', child: Text('No')),
                ],
                onChanged: (value) => rule.value.text = value!,
              )
            else
              TextFormField(
                controller: rule.value,
                validator: _validate,
                onFieldSubmitted: (_) => _apply(),
                keyboardType: widget.field.type == DailyOrderFieldType.number
                    ? const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      )
                    : TextInputType.text,
                decoration: InputDecoration(
                  labelText: 'Value',
                  hintText: widget.field.type == DailyOrderFieldType.date
                      ? 'YYYY-MM-DD'
                      : null,
                  border: const OutlineInputBorder(),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _FilterRule {
  _FilterRule(this.operator, String value)
    : value = TextEditingController(text: value);

  DailyOrderOperator operator;
  final TextEditingController value;
}
