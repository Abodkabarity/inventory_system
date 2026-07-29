import 'package:daily_order/core/theme/app_colors.dart';
import 'package:daily_order/presentation/inventory_dashboard/bloc/inventory_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/additional_request_group.dart';
import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_event.dart';

class InventoryAdditionalPanel extends StatefulWidget {
  final List<AdditionalRequestGroup> requests;

  const InventoryAdditionalPanel({super.key, required this.requests});

  @override
  State<InventoryAdditionalPanel> createState() {
    return _InventoryAdditionalPanelState();
  }
}

class _InventoryAdditionalPanelState extends State<InventoryAdditionalPanel> {
  final Map<String, TextEditingController> qtyControllers = {};
  final Map<String, TextEditingController> noteControllers = {};
  final Map<String, TextEditingController> storeQtyControllers = {};
  final Map<String, TextEditingController> storeNoteControllers = {};

  final Map<String, bool> loadingMap = {};

  final TextEditingController _searchController = TextEditingController();

  String _search = '';
  bool _bulkConfirmRequested = false;

  @override
  void initState() {
    super.initState();
    _synchronizeControllers(widget.requests);
  }

  @override
  void didUpdateWidget(covariant InventoryAdditionalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.requests, widget.requests)) {
      _synchronizeControllers(widget.requests);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();

    _disposeControllerMap(qtyControllers);
    _disposeControllerMap(noteControllers);
    _disposeControllerMap(storeQtyControllers);
    _disposeControllerMap(storeNoteControllers);

    super.dispose();
  }

  void _disposeControllerMap(Map<String, TextEditingController> controllers) {
    for (final controller in controllers.values) {
      controller.dispose();
    }

    controllers.clear();
  }

  void _synchronizeControllers(List<AdditionalRequestGroup> requests) {
    final validIds = requests.map((request) {
      return request.groupId;
    }).toSet();

    _removeUnusedControllers(qtyControllers, validIds);
    _removeUnusedControllers(noteControllers, validIds);
    _removeUnusedControllers(storeQtyControllers, validIds);
    _removeUnusedControllers(storeNoteControllers, validIds);

    loadingMap.removeWhere((id, value) => !validIds.contains(id));

    for (final request in requests) {
      final id = request.groupId;

      qtyControllers.putIfAbsent(
        id,
        () => TextEditingController(
          text: _inventoryFallbackQty(request).toString(),
        ),
      );

      noteControllers.putIfAbsent(
        id,
        () => TextEditingController(text: request.inventoryNote ?? ''),
      );

      final storeQuantity = (request.fulfilledQty ?? 0).toString();

      final storeQuantityController = storeQtyControllers.putIfAbsent(
        id,
        () => TextEditingController(text: storeQuantity),
      );

      if (storeQuantityController.text != storeQuantity) {
        storeQuantityController.text = storeQuantity;
      }

      final storeNote = request.storeNote ?? '';

      final storeNoteController = storeNoteControllers.putIfAbsent(
        id,
        () => TextEditingController(text: storeNote),
      );

      if (storeNoteController.text != storeNote) {
        storeNoteController.text = storeNote;
      }
    }
  }

  void _removeUnusedControllers(
    Map<String, TextEditingController> controllers,
    Set<String> validIds,
  ) {
    final keysToRemove = controllers.keys
        .where((key) => !validIds.contains(key))
        .toList();

    for (final key in keysToRemove) {
      controllers.remove(key)?.dispose();
    }
  }

  num _parseQuantity(String? rawValue, num fallbackValue) {
    final cleanValue = (rawValue ?? '').trim().replaceAll(',', '');

    if (cleanValue.isEmpty) {
      return fallbackValue;
    }

    return num.tryParse(cleanValue) ?? fallbackValue;
  }

  num _inventoryFallbackQty(AdditionalRequestGroup request) {
    final inventoryQuantity = request.inventoryQty;

    if (inventoryQuantity != null && inventoryQuantity > 0) {
      return inventoryQuantity;
    }

    return request.requestQty ?? 0;
  }

  bool _isPending(AdditionalRequestGroup request) {
    final status = request.status.toLowerCase().trim();

    return status == 'pending' || status == 'pending_inventory';
  }

  String _statusBucket(AdditionalRequestGroup request) {
    final status = request.status.toLowerCase().trim();

    if (status == 'pending' || status == 'pending_inventory') {
      return 'pending';
    }

    if (status == 'sent_to_store') {
      return 'sent_to_store';
    }

    if (status == 'done') {
      return 'done';
    }

    if (status == 'rejected') {
      return 'rejected';
    }

    return 'other';
  }

  int _statusPriority(AdditionalRequestGroup request) {
    if (_isPending(request)) {
      final contactLogistic = request.contactLogistic.toLowerCase().trim();

      if (contactLogistic == 'urgent') {
        return 0;
      }

      return 1;
    }

    final status = request.status.toLowerCase().trim();

    if (status == 'sent_to_store') {
      return 2;
    }

    if (status == 'done') {
      return 3;
    }

    if (status == 'rejected') {
      return 4;
    }

    return 5;
  }

  List<AdditionalRequestGroup> _filteredRequests() {
    final query = _search.trim().toLowerCase();

    if (query.isEmpty) {
      return [...widget.requests];
    }

    return widget.requests.where((request) {
      return request.branchName.toLowerCase().contains(query) ||
          request.itemCodes.toLowerCase().contains(query) ||
          request.itemNames.toLowerCase().contains(query);
    }).toList();
  }

  List<List<AdditionalRequestGroup>> _groupRequests(
    List<AdditionalRequestGroup> requests,
  ) {
    final Map<String, List<AdditionalRequestGroup>> groupedRequests = {};

    for (final request in requests) {
      final key = '${request.itemCodes}_${_statusBucket(request)}';

      groupedRequests.putIfAbsent(key, () => []);
      groupedRequests[key]!.add(request);
    }

    final groups = groupedRequests.values.toList();

    groups.sort((firstGroup, secondGroup) {
      final firstPriority = firstGroup.map(_statusPriority).reduce((
        first,
        second,
      ) {
        return first < second ? first : second;
      });

      final secondPriority = secondGroup.map(_statusPriority).reduce((
        first,
        second,
      ) {
        return first < second ? first : second;
      });

      if (firstPriority != secondPriority) {
        return firstPriority.compareTo(secondPriority);
      }

      final firstDate = _latestPendingDate(firstGroup);
      final secondDate = _latestPendingDate(secondGroup);

      return secondDate.compareTo(firstDate);
    });

    return groups;
  }

  DateTime _latestPendingDate(List<AdditionalRequestGroup> group) {
    var latestDate = DateTime(2000);

    for (final request in group) {
      if (_isPending(request) && request.createdAt.isAfter(latestDate)) {
        latestDate = request.createdAt;
      }
    }

    return latestDate;
  }

  Future<void> _confirmAll(BuildContext context) async {
    final List<Map<String, dynamic>> requestsToApprove = [];

    for (final request in widget.requests) {
      if (!_isPending(request)) {
        continue;
      }

      final id = request.groupId;

      final quantity = _parseQuantity(
        qtyControllers[id]?.text,
        _inventoryFallbackQty(request),
      );

      final note = (noteControllers[id]?.text ?? '').trim();

      requestsToApprove.add({
        'id': id,
        'qty': quantity,
        'inventory_qty': quantity,
        'note': note,
        'inventory_note': note,
      });
    }

    if (requestsToApprove.isEmpty) {
      _showNotification(
        context,
        type: _NotificationType.information,
        title: 'No Pending Requests',
        message: 'There are no pending additional requests to confirm.',
      );

      return;
    }

    setState(() {
      _bulkConfirmRequested = true;
    });

    context.read<InventoryBloc>().add(
      ApproveAllInventoryRequests(requestsToApprove),
    );
  }

  void _approveRequest(AdditionalRequestGroup request) {
    final id = request.groupId;

    if (loadingMap[id] == true) {
      return;
    }

    final quantity = _parseQuantity(
      qtyControllers[id]?.text,
      _inventoryFallbackQty(request),
    );

    final note = (noteControllers[id]?.text ?? '').trim();

    setState(() {
      loadingMap[id] = true;
    });

    context.read<InventoryBloc>().add(
      ApproveInventoryRequest(requestId: id, qty: quantity, note: note),
    );
  }

  void _showNotification(
    BuildContext context, {
    required _NotificationType type,
    required String title,
    required String message,
  }) {
    final messenger = ScaffoldMessenger.of(context);

    messenger.hideCurrentSnackBar();

    final configuration = _notificationConfiguration(type);

    messenger.showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        duration: const Duration(seconds: 4),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: configuration.color,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: configuration.color.withValues(alpha: 0.24),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(configuration.icon, color: Colors.white, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      message,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredRequests = _filteredRequests();
    final groupedRequests = _groupRequests(filteredRequests);

    final pendingCount = widget.requests.where(_isPending).length;

    final sentCount = widget.requests.where((request) {
      return request.status.toLowerCase().trim() == 'sent_to_store';
    }).length;

    final doneCount = widget.requests.where((request) {
      return request.status.toLowerCase().trim() == 'done';
    }).length;

    final rejectedCount = widget.requests.where((request) {
      return request.status.toLowerCase().trim() == 'rejected';
    }).length;

    return BlocListener<InventoryBloc, InventoryState>(
      listenWhen: (previous, current) {
        return previous.isBulkLoading && !current.isBulkLoading;
      },
      listener: (context, state) {
        final wasBulkConfirmation = _bulkConfirmRequested;

        final wasSingleConfirmation = loadingMap.isNotEmpty;

        if (mounted) {
          setState(() {
            loadingMap.clear();
            _bulkConfirmRequested = false;
          });
        }

        if (!wasBulkConfirmation && !wasSingleConfirmation) {
          return;
        }

        final success = state.bulkSuccess == true;
        final stateMessage = (state.bulkMessage ?? '').trim();

        _showNotification(
          context,
          type: success ? _NotificationType.success : _NotificationType.error,
          title: success
              ? wasBulkConfirmation
                    ? 'Requests Confirmed'
                    : 'Request Confirmed'
              : 'Confirmation Failed',
          message: stateMessage.isNotEmpty
              ? stateMessage
              : success
              ? wasBulkConfirmation
                    ? 'All pending additional requests were confirmed successfully.'
                    : 'The additional request was confirmed successfully.'
              : 'The request could not be confirmed. Please try again.',
        );
      },
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFFF4F8FB),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFD8E5EC)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF163B51).withValues(alpha: 0.055),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            BlocBuilder<InventoryBloc, InventoryState>(
              buildWhen: (previous, current) {
                return previous.isBulkLoading != current.isBulkLoading;
              },
              builder: (context, state) {
                return _LuxuryPanelHeader(
                  searchController: _searchController,
                  searchValue: _search,
                  pendingCount: pendingCount,
                  sentCount: sentCount,
                  doneCount: doneCount,
                  rejectedCount: rejectedCount,
                  loading: state.isBulkLoading,
                  onSearchChanged: (value) {
                    setState(() {
                      _search = value;
                    });
                  },
                  onClearSearch: () {
                    _searchController.clear();

                    setState(() {
                      _search = '';
                    });
                  },
                  onConfirmAll: pendingCount == 0
                      ? null
                      : () => _confirmAll(context),
                );
              },
            ),
            Expanded(
              child: groupedRequests.isEmpty
                  ? _EmptyRequestsView(searching: _search.trim().isNotEmpty)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 13, 14, 20),
                      physics: const ClampingScrollPhysics(),
                      scrollCacheExtent: const ScrollCacheExtent.pixels(700),
                      addAutomaticKeepAlives: false,
                      addRepaintBoundaries: true,
                      itemCount: groupedRequests.length,
                      itemBuilder: (context, index) {
                        final group = groupedRequests[index];

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: RepaintBoundary(
                            child: _LuxuryProductCard(
                              key: ValueKey(
                                '${group.first.itemCodes}_${_statusBucket(group.first)}',
                              ),
                              group: group,
                              qtyControllers: qtyControllers,
                              noteControllers: noteControllers,
                              storeQtyControllers: storeQtyControllers,
                              storeNoteControllers: storeNoteControllers,
                              loadingMap: loadingMap,
                              isPending: _isPending,
                              statusPriority: _statusPriority,
                              onApprove: _approveRequest,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LuxuryPanelHeader extends StatelessWidget {
  final TextEditingController searchController;
  final String searchValue;

  final int pendingCount;
  final int sentCount;
  final int doneCount;
  final int rejectedCount;

  final bool loading;

  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback? onConfirmAll;

  const _LuxuryPanelHeader({
    required this.searchController,
    required this.searchValue,
    required this.pendingCount,
    required this.sentCount,
    required this.doneCount,
    required this.rejectedCount,
    required this.loading,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onConfirmAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE6F4FA), Color(0xFFF8FCFE)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        border: Border(bottom: BorderSide(color: Color(0xFFD5E7F0))),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 820;

          final identity = _HeaderIdentity(
            pendingCount: pendingCount,
            sentCount: sentCount,
            doneCount: doneCount,
            rejectedCount: rejectedCount,
          );

          final searchField = _LuxurySearchField(
            controller: searchController,
            searchValue: searchValue,
            onChanged: onSearchChanged,
            onClear: onClearSearch,
          );

          final confirmationButton = _ConfirmAllButton(
            loading: loading,
            pendingCount: pendingCount,
            onPressed: onConfirmAll,
          );

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                identity,
                const SizedBox(height: 13),
                searchField,
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: confirmationButton),
              ],
            );
          }

          return Row(
            children: [
              SizedBox(width: 290, child: identity),
              const SizedBox(width: 16),
              Expanded(child: searchField),
              const SizedBox(width: 12),
              SizedBox(width: 190, child: confirmationButton),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderIdentity extends StatelessWidget {
  final int pendingCount;
  final int sentCount;
  final int doneCount;
  final int rejectedCount;

  const _HeaderIdentity({
    required this.pendingCount,
    required this.sentCount,
    required this.doneCount,
    required this.rejectedCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF56BDE5), Color(0xFF178FC8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF178FC8).withValues(alpha: 0.25),
                blurRadius: 15,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(
            Icons.add_shopping_cart_rounded,
            color: Colors.white,
            size: 23,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: const Text(
            'Inventory Additional Requests',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.secondaryColor,
              fontSize: 17,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _LuxurySearchField extends StatefulWidget {
  final TextEditingController controller;
  final String searchValue;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _LuxurySearchField({
    required this.controller,
    required this.searchValue,
    required this.onChanged,
    required this.onClear,
  });

  @override
  State<_LuxurySearchField> createState() {
    return _LuxurySearchFieldState();
  }
}

class _LuxurySearchFieldState extends State<_LuxurySearchField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (value) {
        if (_focused != value) {
          setState(() {
            _focused = value;
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: _focused
              ? [
                  BoxShadow(
                    color: AppColors.primaryColor.withValues(alpha: 0.13),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: TextField(
          controller: widget.controller,
          onChanged: widget.onChanged,
          style: const TextStyle(
            color: AppColors.secondaryColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: 'Search branch, item code, or item name...',
            hintStyle: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: Color(0xFF64748B),
              size: 21,
            ),
            suffixIcon: widget.searchValue.trim().isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: widget.onClear,
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 13),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFD3E2EA)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFD3E2EA)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppColors.primaryColor,
                width: 1.45,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmAllButton extends StatefulWidget {
  final bool loading;
  final int pendingCount;
  final VoidCallback? onPressed;

  const _ConfirmAllButton({
    required this.loading,
    required this.pendingCount,
    required this.onPressed,
  });

  @override
  State<_ConfirmAllButton> createState() {
    return _ConfirmAllButtonState();
  }
}

class _ConfirmAllButtonState extends State<_ConfirmAllButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.loading || widget.onPressed == null;

    return MouseRegion(
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) {
        if (!disabled) {
          setState(() {
            _hovered = true;
          });
        }
      },
      onExit: (_) {
        if (_hovered) {
          setState(() {
            _hovered = false;
          });
        }
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 170),
        scale: _hovered ? 1.018 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: AppColors.primaryColor.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 7),
                    ),
                  ]
                : null,
          ),
          child: ElevatedButton.icon(
            onPressed: widget.loading ? null : widget.onPressed,
            style: ElevatedButton.styleFrom(
              elevation: 0,
              foregroundColor: Colors.white,
              backgroundColor: AppColors.primaryColor,
              disabledForegroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFB4C9D4),
              padding: const EdgeInsets.symmetric(horizontal: 17),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            icon: widget.loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.done_all_rounded, size: 18),
            label: Text(
              widget.loading
                  ? 'Confirming...'
                  : 'Confirm All (${widget.pendingCount})',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ),
    );
  }
}

class _LuxuryProductCard extends StatefulWidget {
  final List<AdditionalRequestGroup> group;

  final Map<String, TextEditingController> qtyControllers;

  final Map<String, TextEditingController> noteControllers;

  final Map<String, TextEditingController> storeQtyControllers;

  final Map<String, TextEditingController> storeNoteControllers;

  final Map<String, bool> loadingMap;

  final bool Function(AdditionalRequestGroup) isPending;

  final int Function(AdditionalRequestGroup) statusPriority;

  final ValueChanged<AdditionalRequestGroup> onApprove;

  const _LuxuryProductCard({
    super.key,
    required this.group,
    required this.qtyControllers,
    required this.noteControllers,
    required this.storeQtyControllers,
    required this.storeNoteControllers,
    required this.loadingMap,
    required this.isPending,
    required this.statusPriority,
    required this.onApprove,
  });

  @override
  State<_LuxuryProductCard> createState() {
    return _LuxuryProductCardState();
  }
}

class _LuxuryProductCardState extends State<_LuxuryProductCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final sortedGroup = [...widget.group];

    sortedGroup.sort((first, second) {
      final firstPriority = widget.statusPriority(first);

      final secondPriority = widget.statusPriority(second);

      if (firstPriority != secondPriority) {
        return firstPriority.compareTo(secondPriority);
      }

      if (widget.isPending(first) && widget.isPending(second)) {
        return second.createdAt.compareTo(first.createdAt);
      }

      return 0;
    });

    final firstRequest = sortedGroup.first;

    final status = _requestStatus(firstRequest.status);

    final urgent = sortedGroup.any((request) {
      return request.contactLogistic.toLowerCase().trim() == 'urgent';
    });

    return MouseRegion(
      onEnter: (_) {
        if (!_hovered) {
          setState(() {
            _hovered = true;
          });
        }
      },
      onExit: (_) {
        if (_hovered) {
          setState(() {
            _hovered = false;
          });
        }
      },
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        offset: _hovered ? const Offset(0, -0.012) : Offset.zero,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: _hovered
                  ? status.color.withValues(alpha: 0.32)
                  : const Color(0xFFDCE6EC),
              width: _hovered ? 1.2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _hovered
                    ? status.color.withValues(alpha: 0.12)
                    : const Color(0xFF163B51).withValues(alpha: 0.05),
                blurRadius: _hovered ? 22 : 12,
                offset: Offset(0, _hovered ? 9 : 5),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: _hovered ? 5 : 4,
                  color: status.color,
                ),
              ),
              Positioned(
                right: -30,
                top: -42,
                child: Container(
                  width: 105,
                  height: 105,
                  decoration: BoxDecoration(
                    color: status.color.withValues(
                      alpha: _hovered ? 0.07 : 0.04,
                    ),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 11, 13, 11),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ProductIdentityHeader(
                      request: firstRequest,
                      status: status,
                      urgent: urgent,
                      requestCount: sortedGroup.length,
                    ),
                    const SizedBox(height: 9),
                    ...List.generate(sortedGroup.length, (index) {
                      final request = sortedGroup[index];

                      final id = request.groupId;

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (index > 0)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Divider(
                                height: 1,
                                color: Color(0xFFE3EBF0),
                              ),
                            ),
                          _RequestContentRow(
                            request: request,
                            pending: widget.isPending(request),
                            loading: widget.loadingMap[id] == true,
                            qtyController: widget.qtyControllers[id]!,
                            noteController: widget.noteControllers[id]!,
                            storeQtyController: widget.storeQtyControllers[id]!,
                            storeNoteController:
                                widget.storeNoteControllers[id]!,
                            onApprove: () {
                              widget.onApprove(request);
                            },
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductIdentityHeader extends StatelessWidget {
  final AdditionalRequestGroup request;
  final _RequestStatus status;

  final bool urgent;
  final int requestCount;

  const _ProductIdentityHeader({
    required this.request,
    required this.status,
    required this.urgent,
    required this.requestCount,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 37,
      child: Row(
        children: [
          Container(
            width: 35,
            height: 35,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: status.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: status.color.withValues(alpha: 0.14)),
            ),
            child: Icon(status.icon, color: status.color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                SelectableText(
                  request.itemCodes,
                  maxLines: 1,
                  style: const TextStyle(
                    color: AppColors.secondaryColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 9),
                Container(width: 1, height: 17, color: const Color(0xFFD8E3E9)),
                const SizedBox(width: 9),
                Expanded(
                  child: SelectableText(
                    request.itemNames,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Color(0xFF334155),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (urgent) ...[
            const SizedBox(width: 8),
            const _LuxuryStatusBadge(
              label: 'URGENT',
              icon: Icons.bolt_rounded,
              color: Color(0xFFF43F5E),
            ),
          ],
          if (requestCount > 1) ...[
            const SizedBox(width: 7),
            _LuxuryStatusBadge(
              label: '$requestCount REQUESTS',
              icon: Icons.layers_rounded,
              color: const Color(0xFF64748B),
            ),
          ],
          const SizedBox(width: 7),
          _LuxuryStatusBadge(
            label: status.label,
            icon: status.icon,
            color: status.color,
          ),
        ],
      ),
    );
  }
}

class _RequestContentRow extends StatelessWidget {
  final AdditionalRequestGroup request;

  final bool pending;
  final bool loading;

  final TextEditingController qtyController;
  final TextEditingController noteController;
  final TextEditingController storeQtyController;
  final TextEditingController storeNoteController;

  final VoidCallback onApprove;

  const _RequestContentRow({
    required this.request,
    required this.pending,
    required this.loading,
    required this.qtyController,
    required this.noteController,
    required this.storeQtyController,
    required this.storeNoteController,
    required this.onApprove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 900;

            if (compact) {
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _BranchIdentity(request: request)),
                      const SizedBox(width: 10),
                      _RequestedQuantityBadge(quantity: request.requestQty),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _RequestControls(
                    pending: pending,
                    loading: loading,
                    qtyController: qtyController,
                    noteController: noteController,
                    storeQtyController: storeQtyController,
                    storeNoteController: storeNoteController,
                    onApprove: onApprove,
                  ),
                ],
              );
            }

            return SizedBox(
              height: 47,
              child: Row(
                children: [
                  SizedBox(
                    width: 190,
                    child: _BranchIdentity(request: request),
                  ),
                  const SizedBox(width: 10),
                  _RequestedQuantityBadge(quantity: request.requestQty),
                  const SizedBox(width: 11),
                  Expanded(
                    child: _RequestControls(
                      pending: pending,
                      loading: loading,
                      qtyController: qtyController,
                      noteController: noteController,
                      storeQtyController: storeQtyController,
                      storeNoteController: storeNoteController,
                      onApprove: onApprove,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        _LuxuryMetricsBar(request: request),
      ],
    );
  }
}

class _BranchIdentity extends StatelessWidget {
  final AdditionalRequestGroup request;

  const _BranchIdentity({required this.request});

  @override
  Widget build(BuildContext context) {
    final formattedDate = DateFormat(
      'dd MMM yyyy • hh:mm a',
    ).format(request.createdAt.toLocal());

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          request.branchName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.secondaryColor,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(
              Icons.schedule_rounded,
              size: 12,
              color: Color(0xFF78909C),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                formattedDate,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF78909C),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RequestedQuantityBadge extends StatelessWidget {
  final dynamic quantity;

  const _RequestedQuantityBadge({required this.quantity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 47,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF7F8), Color(0xFFFFEDF1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: const Color(0xFFF43F5E).withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'REQUESTED',
            style: TextStyle(
              color: Color(0xFFBE123C),
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            quantity?.toString() ?? '0',
            style: const TextStyle(
              color: Color(0xFFE11D48),
              fontSize: 16,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestControls extends StatelessWidget {
  final bool pending;
  final bool loading;

  final TextEditingController qtyController;
  final TextEditingController noteController;
  final TextEditingController storeQtyController;
  final TextEditingController storeNoteController;

  final VoidCallback onApprove;

  const _RequestControls({
    required this.pending,
    required this.loading,
    required this.qtyController,
    required this.noteController,
    required this.storeQtyController,
    required this.storeNoteController,
    required this.onApprove,
  });

  @override
  Widget build(BuildContext context) {
    if (pending) {
      return Row(
        children: [
          SizedBox(
            width: 130,
            child: _LuxuryInputField(
              controller: qtyController,
              label: 'Inventory Confirm',
              numeric: true,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: _LuxuryInputField(
              controller: noteController,
              label: 'Inventory Note',
              icon: Icons.notes_rounded,
            ),
          ),
          const SizedBox(width: 9),
          SizedBox(
            width: 116,
            child: _ConfirmRequestButton(
              loading: loading,
              onPressed: onApprove,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        SizedBox(
          width: 135,
          child: _LuxuryInputField(
            controller: qtyController,
            label: 'Inventory Confirm',
            icon: Icons.inventory_2_rounded,
            numeric: true,
            readOnly: true,
          ),
        ),
        const SizedBox(width: 9),
        SizedBox(
          width: 135,
          child: _LuxuryInputField(
            controller: storeQtyController,
            label: 'Store Supply',
            icon: Icons.local_shipping_rounded,
            numeric: true,
            readOnly: true,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: _LuxuryInputField(
            controller: storeNoteController,
            label: 'Store Note',
            icon: Icons.sticky_note_2_rounded,
            readOnly: true,
          ),
        ),
      ],
    );
  }
}

class _LuxuryInputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData? icon;

  final bool numeric;
  final bool readOnly;

  const _LuxuryInputField({
    required this.controller,
    required this.label,
    this.icon,
    this.numeric = false,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        textAlign: numeric ? TextAlign.center : TextAlign.start,
        style: const TextStyle(
          color: AppColors.secondaryColor,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
          prefixIcon: numeric || icon == null
              ? null
              : Icon(icon, size: 16, color: AppColors.primaryColor),
          filled: true,
          fillColor: readOnly ? const Color(0xFFF0F6F9) : Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 11),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: Color(0xFFB8D7E6)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: Color(0xFFB8D7E6)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(
              color: AppColors.primaryColor,
              width: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmRequestButton extends StatefulWidget {
  final bool loading;
  final VoidCallback onPressed;

  const _ConfirmRequestButton({required this.loading, required this.onPressed});

  @override
  State<_ConfirmRequestButton> createState() {
    return _ConfirmRequestButtonState();
  }
}

class _ConfirmRequestButtonState extends State<_ConfirmRequestButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.loading
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) {
        if (!widget.loading) {
          setState(() {
            _hovered = true;
          });
        }
      },
      onExit: (_) {
        if (_hovered) {
          setState(() {
            _hovered = false;
          });
        }
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        scale: _hovered ? 1.02 : 1,
        child: SizedBox(
          height: 44,
          child: ElevatedButton.icon(
            onPressed: widget.loading ? null : widget.onPressed,
            style: ElevatedButton.styleFrom(
              elevation: 0,
              foregroundColor: Colors.white,
              backgroundColor: const Color(0xFF08B989),
              disabledForegroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF8CDAC3),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
              shadowColor: const Color(0xFF08B989).withValues(alpha: 0.25),
            ),
            icon: widget.loading
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 17),
            label: Text(
              widget.loading ? 'Saving' : 'Confirm',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LuxuryMetricsBar extends StatelessWidget {
  final AdditionalRequestGroup request;

  const _LuxuryMetricsBar({required this.request});

  @override
  Widget build(BuildContext context) {
    final metrics = [
      _MetricModel(
        title: 'Branch Stock',
        value: _formatValue('Branch Stock', request.branchStock),
        icon: Icons.store_rounded,
      ),
      _MetricModel(
        title: 'Store Stock',
        value: _formatValue('Store Stock', request.storeStock),
        icon: Icons.warehouse_rounded,
      ),
      _MetricModel(
        title: 'Sales',
        value: _formatValue('Sales', request.sales),
        icon: Icons.trending_up_rounded,
      ),
      _MetricModel(
        title: 'Final Reorder',
        value: _formatValue('Final Reorder', request.finalReorder),
        icon: Icons.shopping_cart_checkout_rounded,
      ),
      _MetricModel(
        title: 'Today Req',
        value: _formatValue('Today Req', request.todayCount),
        icon: Icons.today_rounded,
      ),
      _MetricModel(
        title: 'Item Status',
        value: _formatValue('Item Status', request.itemStatus),
        icon: Icons.verified_outlined,
      ),
    ];

    return Container(
      height: 39,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEAF5FA), Color(0xFFF0F8FB)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDCEAF1)),
      ),
      child: Row(
        children: List.generate(metrics.length, (index) {
          return Expanded(
            child: Row(
              children: [
                Expanded(child: _LuxuryMetricTile(metric: metrics[index])),
                if (index != metrics.length - 1)
                  Container(
                    width: 1,
                    height: 23,
                    color: const Color(0xFFD4E3EA),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _LuxuryMetricTile extends StatelessWidget {
  final _MetricModel metric;

  const _LuxuryMetricTile({required this.metric});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(metric.icon, size: 12, color: const Color(0xFF7895A5)),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  metric.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            metric.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.secondaryColor,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _LuxuryStatusBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _LuxuryStatusBadge({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 23,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRequestsView extends StatelessWidget {
  final bool searching;

  const _EmptyRequestsView({required this.searching});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 390),
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: const Color(0xFFDCE7ED)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF163B51).withValues(alpha: 0.055),
              blurRadius: 22,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryColor.withValues(alpha: 0.15),
                    AppColors.primaryColor.withValues(alpha: 0.07),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                searching
                    ? Icons.search_off_rounded
                    : Icons.inventory_2_outlined,
                color: AppColors.primaryColor,
                size: 28,
              ),
            ),
            const SizedBox(height: 15),
            Text(
              searching ? 'No Matching Requests' : 'No Additional Requests',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.secondaryColor,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              searching
                  ? 'No additional requests match your current search.'
                  : 'There are no additional requests available at this time.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _NotificationType { success, error, information }

class _NotificationConfiguration {
  final Color color;
  final IconData icon;

  const _NotificationConfiguration({required this.color, required this.icon});
}

_NotificationConfiguration _notificationConfiguration(_NotificationType type) {
  switch (type) {
    case _NotificationType.success:
      return const _NotificationConfiguration(
        color: Color(0xFF059669),
        icon: Icons.check_circle_rounded,
      );

    case _NotificationType.error:
      return const _NotificationConfiguration(
        color: Color(0xFFDC2626),
        icon: Icons.error_outline_rounded,
      );

    case _NotificationType.information:
      return const _NotificationConfiguration(
        color: Color(0xFF258DBF),
        icon: Icons.info_outline_rounded,
      );
  }
}

class _RequestStatus {
  final String label;
  final Color color;
  final IconData icon;

  const _RequestStatus({
    required this.label,
    required this.color,
    required this.icon,
  });
}

_RequestStatus _requestStatus(String rawStatus) {
  final status = rawStatus.toLowerCase().trim();

  switch (status) {
    case 'pending':
    case 'pending_inventory':
      return const _RequestStatus(
        label: 'PENDING',
        color: Color(0xFFF59E0B),
        icon: Icons.schedule_rounded,
      );

    case 'sent_to_store':
      return const _RequestStatus(
        label: 'SENT TO STORE',
        color: Color(0xFF4D7CFE),
        icon: Icons.local_shipping_rounded,
      );

    case 'done':
      return const _RequestStatus(
        label: 'DONE',
        color: Color(0xFF10B981),
        icon: Icons.check_circle_rounded,
      );

    case 'rejected':
      return const _RequestStatus(
        label: 'REJECTED',
        color: Color(0xFFF43F5E),
        icon: Icons.cancel_rounded,
      );

    default:
      return _RequestStatus(
        label: rawStatus.replaceAll('_', ' ').toUpperCase(),
        color: const Color(0xFF64748B),
        icon: Icons.info_outline_rounded,
      );
  }
}

class _MetricModel {
  final String title;
  final String value;
  final IconData icon;

  const _MetricModel({
    required this.title,
    required this.value,
    required this.icon,
  });
}

String _formatValue(String title, dynamic value) {
  if (value == null) {
    return '-';
  }

  if (title == 'Sales') {
    final number = value is num
        ? value
        : num.tryParse(value.toString().replaceAll(',', ''));

    if (number == null) {
      return value.toString();
    }

    return number.toStringAsFixed(2);
  }

  return value.toString();
}
