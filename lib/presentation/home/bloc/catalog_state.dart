import 'package:equatable/equatable.dart';

class CatalogState extends Equatable {
  final bool isLoading;
  final double progress; // 0..1
  final int loaded;
  final int total;
  final String? branchName;

  final String search;

  final List<Map<String, dynamic>> allRows;

  final List<Map<String, dynamic>> viewRows;

  final String? error;

  const CatalogState({
    required this.isLoading,
    required this.progress,
    required this.loaded,
    required this.total,
    required this.search,
    required this.allRows,
    required this.viewRows,
    required this.error,
    required this.branchName,
  });

  factory CatalogState.initial() => const CatalogState(
    isLoading: false,
    progress: 0,
    loaded: 0,
    total: 0,
    branchName: '',
    search: '',
    allRows: [],
    viewRows: [],
    error: null,
  );

  CatalogState copyWith({
    bool? isLoading,
    double? progress,
    int? loaded,
    int? total,
    String? branchName,

    String? search,
    List<Map<String, dynamic>>? allRows,
    List<Map<String, dynamic>>? viewRows,
    String? error,
  }) {
    return CatalogState(
      isLoading: isLoading ?? this.isLoading,
      progress: progress ?? this.progress,
      loaded: loaded ?? this.loaded,
      total: total ?? this.total,
      search: search ?? this.search,
      allRows: allRows ?? this.allRows,
      viewRows: viewRows ?? this.viewRows,
      branchName: branchName ?? this.branchName,
      error: error,
    );
  }

  @override
  List<Object?> get props => [
    isLoading,
    progress,
    loaded,
    total,
    search,
    allRows,
    viewRows,
    branchName,
    error,
  ];
}
