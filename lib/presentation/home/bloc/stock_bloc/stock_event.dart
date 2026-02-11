import 'package:equatable/equatable.dart';

sealed class StockEvent extends Equatable {
  const StockEvent();
  @override
  List<Object?> get props => [];
}

class LoadStockMaps extends StockEvent {
  final String branchName;
  final String storeName;
  const LoadStockMaps({required this.branchName, required this.storeName});

  @override
  List<Object?> get props => [branchName, storeName];
}
