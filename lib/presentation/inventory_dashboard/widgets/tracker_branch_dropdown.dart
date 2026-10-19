import 'dart:math' as math;

import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/store_branch_identity_registry.dart';

/// Keeps raw branch identities for filtering and decorates labels only.
class TrackerBranchDropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  const TrackerBranchDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  static String _label(String branch) => branch == 'ALL'
      ? 'All Branches'
      : StoreBranchIdentityRegistry.displayName(branch);

  static OutlineInputBorder _border({bool focused = false}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: AppColors.primaryColor.withValues(alpha: focused ? 1 : .22),
          width: focused ? 1.5 : 1,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final popupWidth = math.min(360.0, MediaQuery.sizeOf(context).width - 32);
    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: StoreBranchIdentityRegistry.groups,
      builder: (context, _, _) => Theme(
        data: theme.copyWith(
          colorScheme: theme.colorScheme.copyWith(
            primary: AppColors.primaryColor,
            secondary: AppColors.primaryColor,
            onPrimary: Colors.white,
            surface: Colors.white,
            surfaceTint: Colors.transparent,
          ),
          textSelectionTheme: TextSelectionThemeData(
            cursorColor: AppColors.primaryColor,
            selectionColor: AppColors.primaryColor.withValues(alpha: .2),
            selectionHandleColor: AppColors.primaryColor,
          ),
        ),
        child: DropdownSearch<String>(
          key: const ValueKey('tracker-branch-dropdown'),
          selectedItem: value,
          items: (filter, loadProps) => items,
          itemAsString: _label,
          filterFn: (branch, filter) => '${_label(branch)} $branch'
              .toLowerCase()
              .contains(filter.trim().toLowerCase()),
          onSelected: (branch) => onChanged(branch ?? 'ALL'),
          decoratorProps: DropDownDecoratorProps(
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xffF5FAFD),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              border: _border(),
              enabledBorder: _border(),
              focusedBorder: _border(focused: true),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 10, right: 10),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primaryColor.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.storefront_rounded,
                    size: 18,
                    color: AppColors.primaryColor,
                  ),
                ),
              ),
              prefixIconConstraints: const BoxConstraints(minHeight: 32),
            ),
          ),
          dropdownBuilder: (context, selected) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'BRANCH',
                style: TextStyle(
                  color: AppColors.subText,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .8,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _label(selected ?? 'ALL'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.secondaryColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          suffixProps: DropdownSuffixProps(
            clearButtonProps: ClearButtonProps(
              isVisible: value != 'ALL',
              icon: const Icon(Icons.close_rounded, size: 16),
              color: AppColors.subText,
              tooltip: 'All branches',
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 32),
            ),
            dropdownButtonProps: const DropdownButtonProps(
              iconClosed: Icon(Icons.keyboard_arrow_down_rounded, size: 20),
              color: AppColors.primaryColor,
              padding: EdgeInsets.all(4),
              constraints: BoxConstraints(minWidth: 28, minHeight: 32),
            ),
          ),
          popupProps: PopupProps<String>.menu(
            showSearchBox: true,
            showSelectedItems: true,
            searchDelay: Duration.zero,
            fit: FlexFit.loose,
            constraints: BoxConstraints(
              minWidth: popupWidth,
              maxWidth: popupWidth,
              maxHeight: math.min(440, MediaQuery.sizeOf(context).height * .7),
            ),
            menuProps: MenuProps(
              align: MenuAlign.bottomEnd,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 12,
              shadowColor: AppColors.secondaryColor.withValues(alpha: .18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: AppColors.primaryColor.withValues(alpha: .18),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              margin: const EdgeInsets.only(top: 8),
              transitionDuration: const Duration(milliseconds: 180),
              reverseTransitionDuration: const Duration(milliseconds: 120),
              transitionBuilder: (context, animation, secondary, child) =>
                  FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      alignment: Alignment.topRight,
                      scale: Tween<double>(begin: .97, end: 1).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                      child: child,
                    ),
                  ),
            ),
            title: const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 2),
              child: Text(
                'Choose a branch',
                style: TextStyle(
                  color: AppColors.secondaryColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            searchFieldProps: TextFieldProps(
              autofocus: true,
              cursorColor: AppColors.primaryColor,
              style: const TextStyle(
                color: AppColors.secondaryColor,
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: 'Search branches...',
                hintStyle: const TextStyle(color: AppColors.subText),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: AppColors.primaryColor,
                ),
                filled: true,
                fillColor: const Color(0xffF5FAFD),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
                border: _border(),
                enabledBorder: _border(),
                focusedBorder: _border(focused: true),
              ),
            ),
            listViewProps: const ListViewProps(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
            ),
            emptyBuilder: (context, search) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No matching branches',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.subText, fontSize: 13),
              ),
            ),
            itemBuilder: (context, branch, disabled, selected) =>
                ValueListenableBuilder<Map<String, String>>(
                  valueListenable: StoreBranchIdentityRegistry.groups,
                  builder: (context, _, _) => Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primaryColor.withValues(alpha: .13)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          branch == 'ALL'
                              ? Icons.grid_view_rounded
                              : Icons.storefront_outlined,
                          color: selected
                              ? AppColors.primaryColor
                              : AppColors.subText,
                          size: 18,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _label(branch),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.secondaryColor,
                              fontSize: 13,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (selected) ...[
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.primaryColor,
                            size: 19,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
          ),
        ),
      ),
    );
  }
}
