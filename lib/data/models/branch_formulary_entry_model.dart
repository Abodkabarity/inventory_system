import '../../domain/entities/branch_formulary_entry.dart';

class BranchFormularyEntryModel extends BranchFormularyEntry {
  const BranchFormularyEntryModel({
    required super.branchName,
    required super.itemCode,
    super.itemName,
    required super.formularyType,
  });

  static String _inferType(Map<String, dynamic> map) {
    final v1 =
        (map['type'] ??
                map['formulary_type'] ??
                map['revised_branch_formulary'])
            ?.toString()
            .trim();
    if (v1 == null || v1.isEmpty) return 'NON';
    final u = v1.toUpperCase();
    if (u.contains('ESS')) return 'ESSENTIAL';
    if (u.contains('NON')) return 'NON';
    return 'NON';
  }

  factory BranchFormularyEntryModel.fromMap(Map<String, dynamic> map) {
    return BranchFormularyEntryModel(
      branchName: (map['branch_name'] as String?) ?? '',
      itemCode: (map['item_code'] as String?) ?? '',
      itemName: map['item_name'] as String?,
      formularyType: _inferType(map),
    );
  }
}
