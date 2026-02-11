import 'package:equatable/equatable.dart';

enum StockStatus { initial, loading, loaded, failure }

class StockState extends Equatable {
  final StockStatus status;
  final String? error;

  final Map<String, num> storeStockByItemCode;
  final Map<String, num> mismatchDiffByItemCode;
  final Map<String, num> pendingByItemCode;
  final Map<String, num> branchStockFinalByItemCode;

  const StockState({
    required this.status,
    required this.storeStockByItemCode,
    required this.mismatchDiffByItemCode,
    required this.pendingByItemCode,
    required this.branchStockFinalByItemCode,
    this.error,
  });

  factory StockState.initial() => const StockState(
    status: StockStatus.initial,
    storeStockByItemCode: {},
    mismatchDiffByItemCode: {},
    pendingByItemCode: {},
    branchStockFinalByItemCode: {},
  );

  StockState copyWith({
    StockStatus? status,
    String? error,
    Map<String, num>? storeStockByItemCode,
    Map<String, num>? mismatchDiffByItemCode,
    Map<String, num>? pendingByItemCode,
    Map<String, num>? branchStockFinalByItemCode,
  }) {
    return StockState(
      status: status ?? this.status,
      error: error,
      storeStockByItemCode: storeStockByItemCode ?? this.storeStockByItemCode,
      mismatchDiffByItemCode:
          mismatchDiffByItemCode ?? this.mismatchDiffByItemCode,
      pendingByItemCode: pendingByItemCode ?? this.pendingByItemCode,
      branchStockFinalByItemCode:
          branchStockFinalByItemCode ?? this.branchStockFinalByItemCode,
    );
  }

  @override
  List<Object?> get props => [
    status,
    error,
    storeStockByItemCode,
    mismatchDiffByItemCode,
    pendingByItemCode,
    branchStockFinalByItemCode,
  ];
}
