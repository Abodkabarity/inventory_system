import 'package:equatable/equatable.dart';

enum OrderingCalcStatus { initial, calculating, success, failure }

class OrderingCalcState extends Equatable {
  final OrderingCalcStatus status;
  final List<Map<String, dynamic>> rows;
  final String? error;

  const OrderingCalcState({
    required this.status,
    required this.rows,
    this.error,
  });

  factory OrderingCalcState.initial() =>
      const OrderingCalcState(status: OrderingCalcStatus.initial, rows: []);

  OrderingCalcState copyWith({
    OrderingCalcStatus? status,
    List<Map<String, dynamic>>? rows,
    String? error,
  }) {
    return OrderingCalcState(
      status: status ?? this.status,
      rows: rows ?? this.rows,
      error: error,
    );
  }

  @override
  List<Object?> get props => [status, rows, error];
}
