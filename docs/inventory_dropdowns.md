# Inventory Dashboard selection menus

`lib/presentation/widgets/inventory_dropdown.dart` is the shared selection
control for Inventory Dashboard pages, analysis panels and Items Tracker dialogs
and editable table cells. It replaces the native dropdown controls in those
workspaces; multi-selection review dialogs retain their multi-selection behavior.

All selectors use the Stock Overview reference: a rounded blue tinted trigger,
primary-colored icon and arrow, white rounded popup, highlighted current choice
and primary-colored checkmark. The color comes from AppColors.primaryColor.
Ordinary selection and form selection share the same popup and trigger.

Form fields retain validation, save callbacks, disabled state and updates from
their controlled initial value. Popup choice objects distinguish a selected null
option (All branches) from dismissal. Status cell save/rollback handlers are
unchanged; saving disables the selector until the write finishes.

Branch-labelled fields decorate display text through StoreBranchIdentityRegistry,
including open menus when metadata arrives. They return original values to
callbacks; filters, writes and matching keep their raw identities. Branch Settings
and Branch Submission Tracker searches also accept displayed `71` names.

Existing DropdownMenuItem lists remain unchanged, including per-option disabled
states and callbacks. Menu labels wrap to two lines; selected trigger values are
ellipsized to keep compact filters within their existing row height.

Verification covers null options, disabled items, validation/save, controlled
updates, asynchronous 71 metadata, stock workspace interactions, Items Tracker
edits and Stock Check creation dialogs. The MRN Overview golden is updated for
the intentional selector redesign.
