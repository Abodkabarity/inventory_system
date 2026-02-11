import 'package:equatable/equatable.dart';

abstract class CatalogEvent extends Equatable {
  const CatalogEvent();
  @override
  List<Object?> get props => [];
}

/// ضغط زر Create Order -> تحميل item_report
class LoadItemReport extends CatalogEvent {
  const LoadItemReport();
}

/// بحث داخل الجدول
class SearchChanged extends CatalogEvent {
  final String query;
  const SearchChanged(this.query);

  @override
  List<Object?> get props => [query];
}

class UpdateRowField extends CatalogEvent {
  final int index;
  final String field;
  final dynamic value;

  const UpdateRowField({
    required this.index,
    required this.field,
    required this.value,
  });

  @override
  List<Object?> get props => [index, field, value];
}
