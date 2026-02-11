import 'package:equatable/equatable.dart';

class CalcOutput extends Equatable {
  final int demand30;
  final int reorderMin;
  final int reorderMax;
  final String reorderQty;

  const CalcOutput({
    required this.demand30,
    required this.reorderMin,
    required this.reorderMax,
    required this.reorderQty,
  });

  @override
  List<Object?> get props => [demand30, reorderMin, reorderMax, reorderQty];
}
