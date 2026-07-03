import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/date_utils_uae.dart';
import '../../domain/entities.dart';
import '../../domain/mobile_order_repository.dart';

part 'mobile_order_event.dart';
part 'mobile_order_state.dart';

class MobileOrderBloc extends Bloc<MobileOrderEvent, MobileOrderState> {
  final MobileOrderRepository repository;

  MobileOrderBloc(this.repository) : super(MobileOrderState.initial()) {
    on<AppStarted>(_onStarted);
    on<LoginSubmitted>(_onLogin);
    on<LogoutRequested>(_onLogout);
    on<BranchesRequested>(_onBranches);
    on<BranchSelected>(_onBranchSelected);
    on<PickerNameChanged>(_onPickerNameChanged);
    on<OrderRequested>(_onOrderRequested);
    on<CategorySelected>(_onCategorySelected);
    on<BackToCategorySelection>(_onBackToCategorySelection);
    on<PickConfirmed>(_onPickConfirmed);
    on<CategorySubmitted>(_onCategorySubmitted);
    on<MessageCleared>(_onMessageCleared);
  }

  Future<void> _onStarted(
    AppStarted event,
    Emitter<MobileOrderState> emit,
  ) async {
    if (repository.currentSession == null) {
      emit(state.copyWith(status: MobileOrderStatus.unauthenticated));
      return;
    }

    try {
      await repository.ensureAllowedUser();
      add(BranchesRequested());
    } catch (e) {
      await repository.signOut();
      emit(
        state.copyWith(
          status: MobileOrderStatus.unauthenticated,
          error: _cleanError(e),
        ),
      );
    }
  }

  Future<void> _onLogin(
    LoginSubmitted event,
    Emitter<MobileOrderState> emit,
  ) async {
    emit(
      state.copyWith(
        status: MobileOrderStatus.authenticating,
        busyMessage: '',
        error: '',
        info: '',
      ),
    );

    try {
      await repository.signIn(email: event.email, password: event.password);
      add(BranchesRequested());
    } catch (e) {
      emit(
        state.copyWith(
          status: MobileOrderStatus.unauthenticated,
          busyMessage: '',
          error: _cleanError(e),
        ),
      );
    }
  }

  Future<void> _onLogout(
    LogoutRequested event,
    Emitter<MobileOrderState> emit,
  ) async {
    await repository.signOut();
    emit(
      MobileOrderState.initial().copyWith(
        status: MobileOrderStatus.unauthenticated,
      ),
    );
  }

  Future<void> _onBranches(
    BranchesRequested event,
    Emitter<MobileOrderState> emit,
  ) async {
    final requestDate = operationalDateUae();
    emit(
      state.copyWith(
        status: MobileOrderStatus.branchSelection,
        date: requestDate,
        busyMessage: 'Loading submitted branches...',
        error: '',
        info: '',
      ),
    );

    try {
      final branches = await repository.fetchBranchesForDate(requestDate);
      final pickerNames = await repository.loadPickerNames(requestDate);
      emit(
        state.copyWith(
          status: MobileOrderStatus.branchSelection,
          date: requestDate,
          branches: branches,
          pickerNames: pickerNames,
          selectedBranch: branches.length == 1 ? branches.first.name : '',
          clearCategory: true,
          items: const [],
          picked: const {},
          submittedCategories: const {},
          busyMessage: '',
          error: branches.isEmpty
              ? 'No submitted branches found for ${ymd(requestDate)}.'
              : '',
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: MobileOrderStatus.branchSelection,
          busyMessage: '',
          error: _cleanError(e),
        ),
      );
    }
  }

  void _onBranchSelected(BranchSelected event, Emitter<MobileOrderState> emit) {
    emit(
      state.copyWith(
        selectedBranch: event.branch,
        items: const [],
        picked: const {},
        submittedCategories: const {},
        clearCategory: true,
        error: '',
        info: '',
      ),
    );
  }

  void _onPickerNameChanged(
    PickerNameChanged event,
    Emitter<MobileOrderState> emit,
  ) {
    emit(state.copyWith(pickerName: event.name, error: '', info: ''));
  }

  Future<void> _onOrderRequested(
    OrderRequested event,
    Emitter<MobileOrderState> emit,
  ) async {
    if (!state.canContinue) {
      emit(state.copyWith(error: 'Choose branch and write picker name first.'));
      return;
    }

    emit(
      state.copyWith(
        status: MobileOrderStatus.branchSelection,
        busyMessage: 'Loading ${state.selectedBranch} order...',
        error: '',
        info: '',
      ),
    );

    try {
      await repository.savePickerName(state.date, state.pickerName);
      final pickerNames = await repository.loadPickerNames(state.date);
      final items = await repository.fetchBranchOrder(
        branch: state.selectedBranch,
        date: state.date,
      );
      emit(
        state.copyWith(
          status: MobileOrderStatus.categorySelection,
          pickerNames: pickerNames,
          items: items,
          picked: const {},
          submittedCategories: const {},
          clearCategory: true,
          busyMessage: '',
          error: items.isEmpty
              ? 'No daily order rows found for this branch today.'
              : '',
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: MobileOrderStatus.branchSelection,
          busyMessage: '',
          error: _cleanError(e),
        ),
      );
    }
  }

  Future<void> _onCategorySelected(
    CategorySelected event,
    Emitter<MobileOrderState> emit,
  ) async {
    final picked = await repository.loadPicked(
      branch: state.selectedBranch,
      date: state.date,
      category: event.category,
    );
    emit(
      state.copyWith(
        status: MobileOrderStatus.picking,
        selectedCategory: event.category,
        picked: picked,
        busyMessage: '',
        error: '',
        info: '',
      ),
    );
  }

  void _onBackToCategorySelection(
    BackToCategorySelection event,
    Emitter<MobileOrderState> emit,
  ) {
    emit(
      state.copyWith(
        status: MobileOrderStatus.categorySelection,
        clearCategory: true,
        busyMessage: '',
        error: '',
        info: '',
      ),
    );
  }

  Future<void> _onPickConfirmed(
    PickConfirmed event,
    Emitter<MobileOrderState> emit,
  ) async {
    final next = Map<String, PickedItem>.from(state.picked);
    next[event.item.itemCode] = PickedItem(
      itemCode: event.item.itemCode,
      pickedQty: event.qty,
      scannedBarcode: event.scannedBarcode,
      pickedAt: nowUae(),
    );
    emit(
      state.copyWith(
        picked: next,
        error: '',
        info: '${event.item.itemName} confirmed locally.',
      ),
    );

    final category = state.selectedCategory;
    if (category != null) {
      await repository.savePicked(
        branch: state.selectedBranch,
        date: state.date,
        category: category,
        picked: next,
      );
    }
  }

  Future<void> _onCategorySubmitted(
    CategorySubmitted event,
    Emitter<MobileOrderState> emit,
  ) async {
    final category = state.selectedCategory;
    if (category == null || state.visibleItems.isEmpty) return;
    final visiblePicked = {
      for (final item in state.visibleItems)
        if (state.picked.containsKey(item.itemCode))
          item.itemCode: state.picked[item.itemCode]!,
    };
    if (visiblePicked.isEmpty) {
      emit(
        state.copyWith(
          error: 'Scan at least one item before uploading this section.',
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        status: MobileOrderStatus.picking,
        busyMessage: 'Submitting ${category.label} picking result...',
        error: '',
        info: '',
      ),
    );

    try {
      await repository.submitPickedItems(
        branch: state.selectedBranch,
        date: state.date,
        pickerName: state.pickerName,
        category: category,
        items: state.visibleItems,
        picked: visiblePicked,
      );
      emit(
        state.copyWith(
          status: MobileOrderStatus.picking,
          busyMessage: '',
          info:
              '${visiblePicked.length} scanned item(s) uploaded. You can update and submit again anytime.',
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: MobileOrderStatus.picking,
          busyMessage: '',
          error: _cleanError(e),
        ),
      );
    }
  }

  void _onMessageCleared(MessageCleared event, Emitter<MobileOrderState> emit) {
    emit(state.copyWith(error: '', info: '', busyMessage: ''));
  }

  String _cleanError(Object error) {
    final raw = error
        .toString()
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .trim();
    final postgrest = RegExp(
      r'PostgrestException\(message:\s*(.*?),\s*code:',
    ).firstMatch(raw);
    return (postgrest?.group(1) ?? raw).trim();
  }
}
