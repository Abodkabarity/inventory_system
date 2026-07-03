part of 'mobile_order_bloc.dart';

enum MobileOrderStatus {
  booting,
  unauthenticated,
  authenticating,
  branchSelection,
  categorySelection,
  picking,
}

class MobileOrderState extends Equatable {
  final MobileOrderStatus status;
  final DateTime date;
  final List<BranchOption> branches;
  final List<String> pickerNames;
  final String selectedBranch;
  final String pickerName;
  final List<MobileOrderItem> items;
  final PickCategory? selectedCategory;
  final Map<String, PickedItem> picked;
  final Set<PickCategory> submittedCategories;
  final String busyMessage;
  final String error;
  final String info;

  const MobileOrderState({
    required this.status,
    required this.date,
    required this.branches,
    required this.pickerNames,
    required this.selectedBranch,
    required this.pickerName,
    required this.items,
    required this.selectedCategory,
    required this.picked,
    required this.submittedCategories,
    required this.busyMessage,
    required this.error,
    required this.info,
  });

  factory MobileOrderState.initial() {
    return MobileOrderState(
      status: MobileOrderStatus.booting,
      date: operationalDateUae(),
      branches: const [],
      pickerNames: const [],
      selectedBranch: '',
      pickerName: '',
      items: const [],
      selectedCategory: null,
      picked: const {},
      submittedCategories: const {},
      busyMessage: '',
      error: '',
      info: '',
    );
  }

  List<MobileOrderItem> get visibleItems {
    final category = selectedCategory;
    if (category == null) return const [];
    return items.where((e) => e.pickCategory == category).toList();
  }

  int countFor(PickCategory category) {
    return items.where((e) => e.pickCategory == category).length;
  }

  int pickedFor(PickCategory category) {
    return items
        .where(
          (e) => e.pickCategory == category && picked.containsKey(e.itemCode),
        )
        .length;
  }

  bool get canContinue {
    return selectedBranch.trim().isNotEmpty && pickerName.trim().isNotEmpty;
  }

  bool get allVisiblePicked {
    final visible = visibleItems;
    return visible.isNotEmpty &&
        visible.every((e) => picked.containsKey(e.itemCode));
  }

  bool get selectedCategorySubmitted {
    final category = selectedCategory;
    return category != null && submittedCategories.contains(category);
  }

  MobileOrderState copyWith({
    MobileOrderStatus? status,
    DateTime? date,
    List<BranchOption>? branches,
    List<String>? pickerNames,
    String? selectedBranch,
    String? pickerName,
    List<MobileOrderItem>? items,
    PickCategory? selectedCategory,
    bool clearCategory = false,
    Map<String, PickedItem>? picked,
    Set<PickCategory>? submittedCategories,
    String? busyMessage,
    String? error,
    String? info,
  }) {
    return MobileOrderState(
      status: status ?? this.status,
      date: date ?? this.date,
      branches: branches ?? this.branches,
      pickerNames: pickerNames ?? this.pickerNames,
      selectedBranch: selectedBranch ?? this.selectedBranch,
      pickerName: pickerName ?? this.pickerName,
      items: items ?? this.items,
      selectedCategory: clearCategory
          ? null
          : selectedCategory ?? this.selectedCategory,
      picked: picked ?? this.picked,
      submittedCategories: submittedCategories ?? this.submittedCategories,
      busyMessage: busyMessage ?? this.busyMessage,
      error: error ?? this.error,
      info: info ?? this.info,
    );
  }

  @override
  List<Object?> get props => [
    status,
    date,
    branches,
    pickerNames,
    selectedBranch,
    pickerName,
    items,
    selectedCategory,
    picked,
    submittedCategories,
    busyMessage,
    error,
    info,
  ];
}
