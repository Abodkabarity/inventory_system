import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/store_branch_identity_registry.dart';

class _MenuChoice<T> {
  final T? value;
  const _MenuChoice(this.value);
}

Widget _label(
  Widget child,
  bool branchNames,
  Object? value, {
  int maxLines = 2,
}) {
  if (branchNames) {
    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: StoreBranchIdentityRegistry.groups,
      builder: (context, _, _) =>
          _textLabel(child, true, value, maxLines: maxLines),
    );
  }
  return _textLabel(child, false, value, maxLines: maxLines);
}

Widget _textLabel(
  Widget child,
  bool branchNames,
  Object? value, {
  int maxLines = 2,
}) {
  if (child is! Text || child.data == null) return child;
  var text = child.data!;
  if (branchNames && value is String) {
    final display = StoreBranchIdentityRegistry.displayName(value);
    if (display != value && !text.contains(display)) {
      text = text.contains(value) ? text.replaceFirst(value, display) : text;
    }
  }
  return Text(
    text,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      color: AppColors.secondaryColor,
      fontSize: 12,
      height: 1,
      fontWeight: FontWeight.w500,
    ),
  );
}

/// Shared inventory selection menu. Choice objects allow selecting a null
/// value (e.g. All branches) without treating it as dismissing the popup.
class InventoryDropdown<T> extends StatelessWidget {
  final T? value;
  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final Widget? hint, icon, underline;
  final String? label;
  final bool isExpanded, isDense, branchNames;
  final TextStyle? style;
  final Color? dropdownColor;
  final BorderRadius? borderRadius;
  const InventoryDropdown({
    super.key,
    this.value,
    this.items,
    this.onChanged,
    this.hint,
    this.icon,
    this.underline,
    this.label,
    this.isExpanded = false,
    this.isDense = false,
    this.branchNames = false,
    this.style,
    this.dropdownColor,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, String>>(
        valueListenable: StoreBranchIdentityRegistry.groups,
        builder: (context, _, _) => LayoutBuilder(
          builder: (context, size) {
            final options = items ?? <DropdownMenuItem<T>>[];
            final selected = options.where((e) => e.value == value).firstOrNull;
            final branch =
                branchNames ||
                const {
                  'branch',
                  'branches',
                  'select branch',
                }.contains(label?.toLowerCase());
            final suppliedIcon = icon is Icon ? (icon as Icon).icon : null;
            final leading =
                suppliedIcon == null ||
                    const [
                      Icons.keyboard_arrow_down,
                      Icons.keyboard_arrow_down_rounded,
                      Icons.expand_more_rounded,
                      Icons.arrow_drop_down,
                      Icons.arrow_drop_down_rounded,
                    ].contains(suppliedIcon)
                ? (branch
                      ? Icons.store_mall_directory_outlined
                      : Icons.tune_rounded)
                : suppliedIcon;
            final enabled = onChanged != null && options.isNotEmpty;
            final selectedLabel =
                selected?.child ?? hint ?? const Text('Select');
            return SizedBox(
              width: size.hasBoundedWidth ? null : 220,
              child: PopupMenuButton<_MenuChoice<T>>(
                enabled: enabled,
                tooltip: label == null ? 'Choose option' : 'Choose $label',
                position: PopupMenuPosition.under,
                color: Colors.white,
                surfaceTintColor: Colors.transparent,
                elevation: 8,
                constraints: const BoxConstraints(
                  minWidth: 230,
                  maxWidth: 380,
                  maxHeight: 420,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: AppColors.primaryColor.withValues(alpha: .18),
                  ),
                ),
                onSelected: (choice) => onChanged?.call(choice.value),
                itemBuilder: (context) => [
                  for (final item in options)
                    PopupMenuItem<_MenuChoice<T>>(
                      value: _MenuChoice(item.value),
                      enabled: item.enabled,
                      onTap: item.onTap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: item.value == value
                              ? AppColors.primaryColor.withValues(alpha: .12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Opacity(
                          opacity: item.enabled ? 1 : .45,
                          child: Row(
                            children: [
                              Expanded(
                                child: _label(item.child, branch, item.value),
                              ),
                              if (item.value == value)
                                const Padding(
                                  padding: EdgeInsets.only(left: 10),
                                  child: Icon(
                                    Icons.check_rounded,
                                    color: AppColors.primaryColor,
                                    size: 18,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
                child: Opacity(
                  opacity: enabled ? 1 : .5,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 46),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryColor.withValues(alpha: .04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primaryColor.withValues(alpha: .14),
                      ),
                    ),
                    child: Row(
                      children: [
                        IconTheme(
                          data: const IconThemeData(
                            color: AppColors.primaryColor,
                            size: 18,
                          ),
                          child: Icon(
                            leading,
                            color: AppColors.primaryColor,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (label?.isNotEmpty ?? false) ...[
                                Text(
                                  label!.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.subText,
                                    fontSize: 10,
                                    height: 1,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                              ],
                              _label(selectedLabel, branch, value, maxLines: 1),
                            ],
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Icon(
                          Icons.expand_more_rounded,
                          color: AppColors.primaryColor,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
}

/// Keeps Form validation, saving and controlled updates while using the same
/// trigger and popup as ordinary inventory selectors.
class InventoryDropdownFormField<T> extends FormField<T> {
  InventoryDropdownFormField({
    super.key,
    super.initialValue,
    List<DropdownMenuItem<T>>? items,
    ValueChanged<T?>? onChanged,
    InputDecoration decoration = const InputDecoration(),
    Widget? icon,
    bool isExpanded = true,
    TextStyle? style,
    super.validator,
    super.onSaved,
    super.autovalidateMode,
  }) : super(
         enabled: onChanged != null,
         builder: (field) => Column(
           mainAxisSize: MainAxisSize.min,
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
             InventoryDropdown<T>(
               value: field.value,
               items: items,
               isExpanded: isExpanded,
               style: style,
               icon: decoration.prefixIcon ?? icon,
               label: decoration.labelText ?? decoration.hintText,
               hint: decoration.hintText == null
                   ? null
                   : Text(decoration.hintText!),
               onChanged: onChanged == null
                   ? null
                   : (v) {
                       field.didChange(v);
                       onChanged(v);
                     },
             ),
             if (field.errorText != null || decoration.errorText != null)
               Padding(
                 padding: const EdgeInsets.only(top: 5, left: 10),
                 child: Text(
                   field.errorText ?? decoration.errorText!,
                   style: TextStyle(
                     color: Theme.of(field.context).colorScheme.error,
                     fontSize: 12,
                   ),
                 ),
               ),
           ],
         ),
       );
  @override
  FormFieldState<T> createState() => _InventoryDropdownFormFieldState<T>();
}

class _InventoryDropdownFormFieldState<T> extends FormFieldState<T> {
  @override
  void didUpdateWidget(covariant InventoryDropdownFormField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      setValue(widget.initialValue);
    }
  }
}
