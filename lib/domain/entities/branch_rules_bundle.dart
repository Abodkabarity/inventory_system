import 'package:equatable/equatable.dart';

import '../../data/models/assortment_entry_model.dart';
import '../../data/models/branch_formulary_entry_model.dart';
import '../../data/models/tma_entry_model.dart';
import 'max_adj.dart';

class BranchRulesBundle extends Equatable {
  final List<BranchFormularyEntryModel> formulary;
  final List<AssortmentEntryModel> assortment;
  final List<TmaEntryModel> tma;
  final List<MaxAdj> maxAdj;

  const BranchRulesBundle({
    required this.formulary,
    required this.assortment,
    required this.tma,
    required this.maxAdj,
  });

  @override
  List<Object?> get props => [formulary, assortment, tma, maxAdj];
}
