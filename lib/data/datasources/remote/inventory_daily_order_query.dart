import '../../../domain/entities/daily_order_query.dart';

/// PostgREST predicates for the inventory table. Only known column identifiers
/// enter the expressions. User values are quoted independently of operators.
class InventoryDailyOrderQuery {
  InventoryDailyOrderQuery(this.query);

  final DailyOrderQuery query;

  String get sortColumn =>
      DailyOrderField.fields[query.sort]?.column ?? 'item_code';

  List<String> get orderColumns =>
      <String>{sortColumn, 'item_code', 'branch'}.toList();

  static final selectColumns = {
    for (final field in DailyOrderField.fields.values) field.column,
  }.join(',');

  Map<String, dynamic> get filterRequest => {
    'run_date': query.runDate,
    'branch': query.branch,
    'search': query.search,
    'branch_matches': query.displayedBranchMatches,
    'sort': sortColumn,
    'ascending': query.ascending,
    'filters': [
      for (final entry in query.filters.entries)
        if (DailyOrderField.fields[entry.key] case final field?)
          {
            'column': field.column,
            if (entry.value.values case final selected?) ...{
              'values': selected.toList(),
              'exclude': entry.value.excludeValues,
            } else ...{
              'match_any': entry.value.matchAny,
              'rules': [
                for (final rule in entry.value.rules)
                  {'operator': rule.operator.name, 'value': rule.value},
              ],
            },
          },
    ],
  };

  Map<String, Object?> cursorValues(DailyOrderCursor cursor) => {
    sortColumn: cursor.sortValue,
    'item_code': cursor.itemCode,
    'branch': cursor.branch,
  };

  Iterable<String> get predicates sync* {
    if (query.search.isNotEmpty) {
      yield [
        for (final column in ['item_name', 'item_code', 'barcode', 'branch'])
          _textMatch(column, query.search, leading: true, trailing: true),
        for (final branch in query.displayedBranchMatches)
          _textMatch('branch', branch),
      ].join(',');
    }

    for (final entry in query.filters.entries) {
      final field = DailyOrderField.fields[entry.key];
      if (field == null || entry.value.rules.isEmpty) continue;

      final conditions = entry.value.rules
          .map((rule) => _condition(field, rule))
          .join(',');
      yield entry.value.matchAny ? conditions : 'and($conditions)';
    }
  }

  String after(DailyOrderCursor cursor) {
    final values = cursorValues(cursor);
    final alternatives = <String>[];
    final equal = <String>[];
    for (final (index, column) in orderColumns.indexed) {
      final value = values[column];
      if (value == null) {
        equal.add('$column.is.null');
        continue;
      }

      final literal = _quote(value.toString());
      final direction = index == 0 && !query.ascending ? 'lt' : 'gt';
      // A nullable leading sort key always puts nulls after all known values.
      final comparison =
          index == 0 && column != 'item_code' && column != 'branch'
          ? 'or($column.$direction.$literal,$column.is.null)'
          : '$column.$direction.$literal';
      alternatives.add(
        equal.isEmpty ? comparison : 'and(${equal.join(',')},$comparison)',
      );
      equal.add('$column.eq.$literal');
    }
    return alternatives.join(',');
  }

  String _condition(DailyOrderField field, DailyOrderRule rule) {
    final column = field.column;
    final value = rule.value;
    final isText = field.type == DailyOrderFieldType.text;
    return switch (rule.operator) {
      DailyOrderOperator.contains => _textMatch(
        column,
        value,
        leading: true,
        trailing: true,
      ),
      DailyOrderOperator.doesNotContain => _textMatch(
        column,
        value,
        leading: true,
        trailing: true,
        negate: true,
      ),
      DailyOrderOperator.startsWith => _textMatch(
        column,
        value,
        trailing: true,
      ),
      DailyOrderOperator.endsWith => _textMatch(column, value, leading: true),
      DailyOrderOperator.equals =>
        isText ? _textMatch(column, value) : '$column.eq.${_quote(value)}',
      DailyOrderOperator.notEqual =>
        isText
            ? _textMatch(column, value, negate: true)
            : '$column.neq.${_quote(value)}',
      DailyOrderOperator.greaterThan => '$column.gt.${_quote(value)}',
      DailyOrderOperator.atLeast => '$column.gte.${_quote(value)}',
      DailyOrderOperator.lessThan => '$column.lt.${_quote(value)}',
      DailyOrderOperator.atMost => '$column.lte.${_quote(value)}',
      DailyOrderOperator.isEmpty =>
        isText ? 'or($column.is.null,$column.eq."")' : '$column.is.null',
      DailyOrderOperator.isNotEmpty =>
        isText
            ? 'and($column.not.is.null,$column.neq."")'
            : '$column.not.is.null',
    };
  }

  static String _quote(String value) =>
      '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  static String _textMatch(
    String column,
    String value, {
    bool leading = false,
    bool trailing = false,
    bool negate = false,
  }) {
    final modifier = negate ? 'not.' : '';
    // PostgREST treats * as a LIKE wildcard even inside a quoted value.
    if (value.contains('*')) {
      final regex =
          '${leading ? '' : '^'}${RegExp.escape(value)}'
          '${trailing ? '' : r'$'}';
      return '$column.${modifier}imatch.${_quote(regex)}';
    }
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final pattern = '${leading ? '%' : ''}$escaped${trailing ? '%' : ''}';
    return '$column.${modifier}ilike.${_quote(pattern)}';
  }
}
