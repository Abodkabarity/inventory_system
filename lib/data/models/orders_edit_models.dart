class FinalReorderEdit {
  final num autoQty;
  final num editedQty;

  const FinalReorderEdit({required this.autoQty, required this.editedQty});

  bool get isChanged => editedQty != autoQty;

  FinalReorderEdit copyWith({num? autoQty, num? editedQty}) {
    return FinalReorderEdit(
      autoQty: autoQty ?? this.autoQty,
      editedQty: editedQty ?? this.editedQty,
    );
  }
}
