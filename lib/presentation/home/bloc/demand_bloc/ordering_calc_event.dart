import 'package:equatable/equatable.dart';

sealed class OrderingCalcEvent extends Equatable {
  const OrderingCalcEvent();
  @override
  List<Object?> get props => [];
}

class CalculateOrderingColumns extends OrderingCalcEvent {
  final List<Map<String, dynamic>> rows;
  const CalculateOrderingColumns(this.rows);

  @override
  List<Object?> get props => [rows];
}
