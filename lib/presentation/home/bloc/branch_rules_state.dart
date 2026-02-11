import 'package:equatable/equatable.dart';

enum BranchRulesStatus { initial, loading, loaded, failure }

class BranchRulesState extends Equatable {
  final BranchRulesStatus status;
  final Map<String, num> demand30ByItemCode;

  final Map<String, String> formularyTypeByItemCode;
  final Map<String, Map<String, dynamic>> assortmentByItemCode;
  final Map<String, Map<String, dynamic>> tmaByItemCode;

  // ✅ NEW: item_code -> max_adj row
  final Map<String, Map<String, dynamic>> maxAdjByItemCode;

  final String? error;

  const BranchRulesState({
    required this.status,
    required this.formularyTypeByItemCode,
    required this.assortmentByItemCode,
    required this.tmaByItemCode,
    required this.maxAdjByItemCode,
    required this.demand30ByItemCode,

    this.error,
  });

  factory BranchRulesState.initial() => const BranchRulesState(
    status: BranchRulesStatus.initial,
    formularyTypeByItemCode: {},
    assortmentByItemCode: {},
    tmaByItemCode: {},
    maxAdjByItemCode: {},
    demand30ByItemCode: {},

    error: null,
  );

  BranchRulesState copyWith({
    BranchRulesStatus? status,
    Map<String, String>? formularyTypeByItemCode,
    Map<String, Map<String, dynamic>>? assortmentByItemCode,
    Map<String, Map<String, dynamic>>? tmaByItemCode,
    Map<String, Map<String, dynamic>>? maxAdjByItemCode,
    Map<String, num>? demand30ByItemCode,

    String? error,
  }) {
    return BranchRulesState(
      status: status ?? this.status,
      formularyTypeByItemCode:
          formularyTypeByItemCode ?? this.formularyTypeByItemCode,
      assortmentByItemCode: assortmentByItemCode ?? this.assortmentByItemCode,
      tmaByItemCode: tmaByItemCode ?? this.tmaByItemCode,
      maxAdjByItemCode: maxAdjByItemCode ?? this.maxAdjByItemCode,
      demand30ByItemCode: demand30ByItemCode ?? this.demand30ByItemCode,
      error: error,
    );
  }

  @override
  List<Object?> get props => [
    status,
    formularyTypeByItemCode,
    assortmentByItemCode,
    tmaByItemCode,
    maxAdjByItemCode,
    demand30ByItemCode,
    error,
  ];
}
