import 'package:daily_order/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/branch_setting.dart';
import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_event.dart';
import '../bloc/inventory_state.dart';

class BranchSettingPage extends StatefulWidget {
  const BranchSettingPage({super.key});

  @override
  State<BranchSettingPage> createState() => _BranchSettingPageState();
}

class _BranchSettingPageState extends State<BranchSettingPage> {
  static const _allZones = 'All Zones';
  static const _allAreas = 'All Areas';
  static const _allTypes = 'All Types';
  static const _allStatuses = 'All Status';
  static const _activeStatus = 'Active';
  static const _inactiveStatus = 'Inactive';

  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _zoneFilter = _allZones;
  String _areaFilter = _allAreas;
  String _typeFilter = _allTypes;
  String _statusFilter = _allStatuses;

  @override
  void initState() {
    super.initState();
    context.read<InventoryBloc>().add(LoadBranchSettings());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<BranchSetting> _filter(List<BranchSetting> rows) {
    final q = _query.trim().toLowerCase();
    return rows.where((b) {
      final matchesSearch =
          q.isEmpty ||
          b.branchName.toLowerCase().contains(q) ||
          b.email.toLowerCase().contains(q) ||
          b.zone.toLowerCase().contains(q) ||
          b.zoneManager.toLowerCase().contains(q) ||
          b.zoneManagerEmail.toLowerCase().contains(q) ||
          b.area.toLowerCase().contains(q) ||
          b.branchType.toLowerCase().contains(q);
      final matchesZone = _zoneFilter == _allZones || b.zone == _zoneFilter;
      final matchesArea = _areaFilter == _allAreas || b.area == _areaFilter;
      final matchesType =
          _typeFilter == _allTypes || b.branchType == _typeFilter;
      final matchesStatus =
          _statusFilter == _allStatuses ||
          (_statusFilter == _activeStatus && b.isActive) ||
          (_statusFilter == _inactiveStatus && !b.isActive);
      return matchesSearch &&
          matchesZone &&
          matchesArea &&
          matchesType &&
          matchesStatus;
    }).toList();
  }

  List<String> _options(Iterable<String> values, String allLabel) {
    final cleaned =
        values.map((v) => v.trim()).where((v) => v.isNotEmpty).toSet().toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [allLabel, ...cleaned];
  }

  Future<void> _openEditor({BranchSetting? branch}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider.value(
        value: context.read<InventoryBloc>(),
        child: _BranchSettingDialog(branch: branch),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<InventoryBloc, InventoryState>(
      listenWhen: (p, c) =>
          p.branchSettingsError != c.branchSettingsError ||
          p.branchSettingsMessage != c.branchSettingsMessage,
      listener: (context, state) {
        if (state.branchSettingsMessage.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.branchSettingsMessage),
              backgroundColor: const Color(0xff059669),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        if (state.branchSettingsError.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.branchSettingsError),
              backgroundColor: const Color(0xffDC2626),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      buildWhen: (p, c) =>
          p.branchSettings != c.branchSettings ||
          p.isBranchSettingsLoading != c.isBranchSettingsLoading ||
          p.isBranchSettingsSaving != c.isBranchSettingsSaving,
      builder: (context, state) {
        final zoneOptions = _options(
          state.branchSettings.map((b) => b.zone),
          _allZones,
        );
        final areaOptions = _options(
          state.branchSettings.map((b) => b.area),
          _allAreas,
        );
        final typeOptions = _options(
          state.branchSettings.map((b) => b.branchType),
          _allTypes,
        );
        const statusOptions = [_allStatuses, _activeStatus, _inactiveStatus];
        final zoneValue = zoneOptions.contains(_zoneFilter)
            ? _zoneFilter
            : _allZones;
        final areaValue = areaOptions.contains(_areaFilter)
            ? _areaFilter
            : _allAreas;
        final typeValue = typeOptions.contains(_typeFilter)
            ? _typeFilter
            : _allTypes;
        final statusValue = statusOptions.contains(_statusFilter)
            ? _statusFilter
            : _allStatuses;
        _zoneFilter = zoneValue;
        _areaFilter = areaValue;
        _typeFilter = typeValue;
        _statusFilter = statusValue;
        final rows = _filter(state.branchSettings);
        final active = state.branchSettings.where((b) => b.isActive).length;
        final inactive = state.branchSettings.length - active;

        return Container(
          color: const Color(0xffF4F7FB),
          child: Column(
            children: [
              _Header(
                total: state.branchSettings.length,
                active: active,
                inactive: inactive,
                onAdd: () => _openEditor(),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
                  children: [
                    _StatsRow(
                      total: state.branchSettings.length,
                      active: active,
                      inactive: inactive,
                    ),
                    const SizedBox(height: 18),
                    _Toolbar(
                      controller: _searchController,
                      saving: state.isBranchSettingsSaving,
                      onChanged: (v) => setState(() => _query = v),
                      onRefresh: () {
                        context.read<InventoryBloc>().add(LoadBranchSettings());
                      },
                      zoneOptions: zoneOptions,
                      areaOptions: areaOptions,
                      typeOptions: typeOptions,
                      statusOptions: statusOptions,
                      zoneValue: zoneValue,
                      areaValue: areaValue,
                      typeValue: typeValue,
                      statusValue: statusValue,
                      onZoneChanged: (v) =>
                          setState(() => _zoneFilter = v ?? _allZones),
                      onAreaChanged: (v) =>
                          setState(() => _areaFilter = v ?? _allAreas),
                      onTypeChanged: (v) =>
                          setState(() => _typeFilter = v ?? _allTypes),
                      onStatusChanged: (v) =>
                          setState(() => _statusFilter = v ?? _allStatuses),
                      onClearFilters: () {
                        setState(() {
                          _query = '';
                          _zoneFilter = _allZones;
                          _areaFilter = _allAreas;
                          _typeFilter = _allTypes;
                          _statusFilter = _allStatuses;
                          _searchController.clear();
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    _BranchesTable(
                      rows: rows,
                      loading: state.isBranchSettingsLoading,
                      onEdit: (branch) => _openEditor(branch: branch),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final int total;
  final int active;
  final int inactive;
  final VoidCallback onAdd;

  const _Header({
    required this.total,
    required this.active,
    required this.inactive,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(34, 28, 30, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xff06B6D4), Color(0xff2563EB)],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: .24)),
            ),
            child: const Icon(
              Icons.tune_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Branch Setting',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Manage branch limits, order days, submit window, zones, area, and activation.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .88),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          _HeaderMetric(label: 'Total', value: '$total'),
          const SizedBox(width: 10),
          _HeaderMetric(label: 'Active', value: '$active'),
          const SizedBox(width: 10),
          _HeaderMetric(label: 'Inactive', value: '$inactive'),
          const SizedBox(width: 14),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_business_rounded),
            label: const Text('Add Branch'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xff2563EB),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  final String label;
  final String value;

  const _HeaderMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 90,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .20)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .78),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final int total;
  final int active;
  final int inactive;

  const _StatsRow({
    required this.total,
    required this.active,
    required this.inactive,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatCard(
          title: 'Total Branches',
          value: '$total',
          icon: Icons.storefront_rounded,
          color: const Color(0xff2563EB),
        ),
        const SizedBox(width: 14),
        _StatCard(
          title: 'Active Branches',
          value: '$active',
          icon: Icons.check_circle_rounded,
          color: const Color(0xff10B981),
        ),
        const SizedBox(width: 14),
        _StatCard(
          title: 'Inactive',
          value: '$inactive',
          icon: Icons.pause_circle_filled_rounded,
          color: const Color(0xffEF4444),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xffE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .035),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xff64748B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Color(0xff0F172A),
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final TextEditingController controller;
  final bool saving;
  final ValueChanged<String> onChanged;
  final VoidCallback onRefresh;
  final List<String> zoneOptions;
  final List<String> areaOptions;
  final List<String> typeOptions;
  final List<String> statusOptions;
  final String zoneValue;
  final String areaValue;
  final String typeValue;
  final String statusValue;
  final ValueChanged<String?> onZoneChanged;
  final ValueChanged<String?> onAreaChanged;
  final ValueChanged<String?> onTypeChanged;
  final ValueChanged<String?> onStatusChanged;
  final VoidCallback onClearFilters;

  const _Toolbar({
    required this.controller,
    required this.saving,
    required this.onChanged,
    required this.onRefresh,
    required this.zoneOptions,
    required this.areaOptions,
    required this.typeOptions,
    required this.statusOptions,
    required this.zoneValue,
    required this.areaValue,
    required this.typeValue,
    required this.statusValue,
    required this.onZoneChanged,
    required this.onAreaChanged,
    required this.onTypeChanged,
    required this.onStatusChanged,
    required this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    final hasFilters =
        controller.text.trim().isNotEmpty ||
        zoneValue != _BranchSettingPageState._allZones ||
        areaValue != _BranchSettingPageState._allAreas ||
        typeValue != _BranchSettingPageState._allTypes ||
        statusValue != _BranchSettingPageState._allStatuses;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffD8E5F3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  decoration: InputDecoration(
                    hintText:
                        'Search branch, email, zone, manager, area, or type...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: AppColors.backgroundWidget,
                    contentPadding: const EdgeInsets.symmetric(vertical: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: AppColors.primaryColor,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: AppColors.primaryColor,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: AppColors.primaryColor,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filledTonal(
                onPressed: saving ? null : onRefresh,
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: AppColors.primaryColor,
                ),
                style: IconButton.styleFrom(backgroundColor: Colors.white),
                tooltip: 'Refresh branches',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _FilterDropdown(
                  label: 'Status',
                  icon: Icons.verified_rounded,
                  value: statusValue,
                  values: statusOptions,
                  onChanged: onStatusChanged,
                  color: const Color(0xff10B981),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _FilterDropdown(
                  label: 'Zone',
                  icon: Icons.place_rounded,
                  value: zoneValue,
                  values: zoneOptions,
                  onChanged: onZoneChanged,
                  color: const Color(0xff2563EB),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _FilterDropdown(
                  label: 'Area',
                  icon: Icons.map_rounded,
                  value: areaValue,
                  values: areaOptions,
                  onChanged: onAreaChanged,
                  color: const Color(0xff0D9488),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _FilterDropdown(
                  label: 'Branch Type',
                  icon: Icons.storefront_rounded,
                  value: typeValue,
                  values: typeOptions,
                  onChanged: onTypeChanged,
                  color: const Color(0xff7C3AED),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: hasFilters ? onClearFilters : null,
                icon: const Icon(Icons.filter_alt_off_rounded),
                label: const Text('Clear'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                  foregroundColor: const Color(0xffEF4444),
                  side: BorderSide(
                    color: hasFilters
                        ? const Color(0xffFCA5A5)
                        : const Color(0xffE2E8F0),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final String label;
  final IconData icon;
  final String value;
  final List<String> values;
  final ValueChanged<String?> onChanged;
  final Color color;

  const _FilterDropdown({
    required this.label,
    required this.icon,
    required this.value,
    required this.values,
    required this.onChanged,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: values.contains(value) ? value : values.first,
      isExpanded: true,
      items: values
          .map(
            (v) => DropdownMenuItem<String>(
              value: v,
              child: Text(
                v,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: color),
        filled: true,
        fillColor: color.withValues(alpha: .06),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color.withValues(alpha: .16)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color.withValues(alpha: .16)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: 1.4),
        ),
      ),
    );
  }
}

class _BranchesTable extends StatelessWidget {
  final List<BranchSetting> rows;
  final bool loading;
  final ValueChanged<BranchSetting> onEdit;

  const _BranchesTable({
    required this.rows,
    required this.loading,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffD8E5F3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xffE2E8F0))),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.settings_suggest_rounded,
                  color: Color(0xff0EA5E9),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Branches Configuration',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xff0F172A),
                  ),
                ),
              ],
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(42),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primaryColor),
              ),
            )
          else if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(42),
              child: Text(
                'No branches found.',
                style: TextStyle(color: Color(0xff64748B)),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: const WidgetStatePropertyAll(
                  Color(0xffEAF4FF),
                ),
                headingTextStyle: const TextStyle(
                  color: Color(0xff334155),
                  fontWeight: FontWeight.w900,
                ),
                dataTextStyle: const TextStyle(
                  color: Color(0xff0F172A),
                  fontWeight: FontWeight.w700,
                ),
                dataRowMinHeight: 70,
                dataRowMaxHeight: 88,
                headingRowHeight: 58,
                columnSpacing: 18,
                horizontalMargin: 18,
                dividerThickness: .8,
                border: TableBorder.all(color: const Color(0xffE2E8F0)),
                columns: const [
                  DataColumn(label: Text('Branch')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Zone')),
                  DataColumn(label: Text('Zone Manager')),
                  DataColumn(label: Text('Area')),
                  DataColumn(label: Text('Type')),
                  DataColumn(label: Text('Order Days')),
                  DataColumn(label: Text('Submit Window')),
                  DataColumn(label: Text('Limits')),
                  DataColumn(label: Text('Action')),
                ],
                rows: rows.asMap().entries.map((entry) {
                  final b = entry.value;
                  return DataRow(
                    color: WidgetStatePropertyAll(
                      entry.key.isEven ? Colors.white : const Color(0xffF8FAFC),
                    ),
                    cells: [
                      DataCell(_BranchNameCell(branch: b)),
                      DataCell(_StatusPill(active: b.isActive)),
                      DataCell(
                        _InfoPill(
                          text: b.zone,
                          color: const Color(0xff2563EB),
                          width: 110,
                        ),
                      ),
                      DataCell(_ZoneManagerCell(branch: b)),
                      DataCell(
                        _InfoPill(
                          text: b.area,
                          color: const Color(0xff0D9488),
                          width: 120,
                        ),
                      ),
                      DataCell(_TypePill(type: b.branchType)),
                      DataCell(_DaysWrap(days: b.orderDays)),
                      DataCell(
                        Text(
                          '${b.submitStartHour}:00 -> ${b.submitEndHour}:00',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      DataCell(_LimitsCell(branch: b)),
                      DataCell(
                        FilledButton.icon(
                          onPressed: () => onEdit(b),
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          label: const Text('Edit'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xff2563EB),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _BranchNameCell extends StatelessWidget {
  final BranchSetting branch;

  const _BranchNameCell({required this.branch});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xffE0F2FE),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.store_rounded,
              color: Color(0xff0284C7),
              size: 19,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              branch.branchName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xff0F172A),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String text;
  final Color color;
  final double width;

  const _InfoPill({
    required this.text,
    required this.color,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: .16)),
        ),
        child: Text(
          text.trim().isEmpty ? '-' : text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _ZoneManagerCell extends StatelessWidget {
  final BranchSetting branch;

  const _ZoneManagerCell({required this.branch});

  @override
  Widget build(BuildContext context) {
    final name = branch.zoneManager.trim();
    final email = branch.zoneManagerEmail.trim();
    return SizedBox(
      width: 220,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xffF0FDFA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xff99F6E4)),
        ),
        child: Text(
          name.isEmpty ? '-' : name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.secondaryColor,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  final String type;

  const _TypePill({required this.type});

  @override
  Widget build(BuildContext context) {
    final lower = type.toLowerCase();
    final color = lower.contains('online')
        ? const Color(0xff2563EB)
        : lower.contains('retail')
        ? const Color(0xff059669)
        : const Color(0xff64748B);
    return _InfoPill(text: type, color: color, width: 110);
  }
}

class _LimitsCell extends StatelessWidget {
  final BranchSetting branch;

  const _LimitsCell({required this.branch});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _MiniLimit(label: 'Max', value: branch.maxAdjLimit),
          _MiniLimit(label: 'Increase', value: branch.orderIncreaseLimit),
          _MiniLimit(label: 'Edit', value: branch.orderEditLimit),
          _MiniLimit(label: 'Add', value: branch.additionalOrderLimit),
        ],
      ),
    );
  }
}

class _MiniLimit extends StatelessWidget {
  final String label;
  final int value;

  const _MiniLimit({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xffF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xffCBD5E1)),
      ),
      child: Text(
        '$label $value',
        style: const TextStyle(
          color: Color(0xff334155),
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool active;

  const _StatusPill({required this.active});

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xff059669) : const Color(0xffDC2626);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .24)),
      ),
      child: Text(
        active ? 'ACTIVE' : 'INACTIVE',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _DaysWrap extends StatelessWidget {
  final List<String> days;

  const _DaysWrap({required this.days});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: days.isEmpty
            ? [
                const Text(
                  'No days',
                  style: TextStyle(color: Color(0xff94A3B8)),
                ),
              ]
            : days
                  .map(
                    (day) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xffEEF2FF),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xffC7D2FE)),
                      ),
                      child: Text(
                        day.substring(0, day.length < 3 ? day.length : 3),
                        style: const TextStyle(
                          color: Color(0xff4F46E5),
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  )
                  .toList(),
      ),
    );
  }
}

class _BranchSettingDialog extends StatefulWidget {
  final BranchSetting? branch;

  const _BranchSettingDialog({this.branch});

  @override
  State<_BranchSettingDialog> createState() => _BranchSettingDialogState();
}

class _BranchSettingDialogState extends State<_BranchSettingDialog> {
  static const _days = [
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  late BranchSetting _value;
  late final TextEditingController _branch;
  late final TextEditingController _email;
  late final TextEditingController _zone;
  late final TextEditingController _zoneManager;
  late final TextEditingController _zoneManagerEmail;
  late final TextEditingController _area;
  late final TextEditingController _type;
  late final TextEditingController _start;
  late final TextEditingController _end;
  late final TextEditingController _max;
  late final TextEditingController _increase;
  late final TextEditingController _edit;
  late final TextEditingController _additional;

  @override
  void initState() {
    super.initState();
    _value = widget.branch ?? BranchSetting.empty();
    _branch = TextEditingController(text: _value.branchName);
    _email = TextEditingController(text: _value.email);
    _zone = TextEditingController(text: _value.zone);
    _zoneManager = TextEditingController(text: _value.zoneManager);
    _zoneManagerEmail = TextEditingController(text: _value.zoneManagerEmail);
    _area = TextEditingController(text: _value.area);
    _type = TextEditingController(text: _value.branchType);
    _start = TextEditingController(text: '${_value.submitStartHour}');
    _end = TextEditingController(text: '${_value.submitEndHour}');
    _max = TextEditingController(text: '${_value.maxAdjLimit}');
    _increase = TextEditingController(text: '${_value.orderIncreaseLimit}');
    _edit = TextEditingController(text: '${_value.orderEditLimit}');
    _additional = TextEditingController(text: '${_value.additionalOrderLimit}');
  }

  @override
  void dispose() {
    _branch.dispose();
    _email.dispose();
    _zone.dispose();
    _zoneManager.dispose();
    _zoneManagerEmail.dispose();
    _area.dispose();
    _type.dispose();
    _start.dispose();
    _end.dispose();
    _max.dispose();
    _increase.dispose();
    _edit.dispose();
    _additional.dispose();
    super.dispose();
  }

  int _int(TextEditingController c, int fallback) {
    return int.tryParse(c.text.trim()) ?? fallback;
  }

  void _save() {
    final branchName = _branch.text.trim();
    if (branchName.isEmpty) return;

    final next = _value.copyWith(
      branchName: branchName,
      email: _email.text.trim(),
      zone: _zone.text.trim(),
      zoneManager: _zoneManager.text.trim(),
      zoneManagerEmail: _zoneManagerEmail.text.trim(),
      area: _area.text.trim(),
      branchType: _type.text.trim(),
      submitStartHour: _int(_start, 21).clamp(0, 24),
      submitEndHour: _int(_end, 8).clamp(0, 24),
      maxAdjLimit: _int(_max, 50).clamp(0, 100000),
      orderIncreaseLimit: _int(_increase, 10).clamp(0, 100000),
      orderEditLimit: _int(_edit, 50).clamp(0, 100000),
      additionalOrderLimit: _int(_additional, 15).clamp(0, 100000),
    );

    context.read<InventoryBloc>().add(
      SaveBranchSetting(
        branch: next,
        originalBranchName: widget.branch?.branchName,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(28),
      child: Container(
        width: 880,
        constraints: const BoxConstraints(maxHeight: 760),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .16),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 22, 18, 18),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xffEFF6FF), Color(0xffECFEFF)],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xffDBEAFE),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.add_business_rounded,
                      color: Color(0xff2563EB),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.branch == null
                              ? 'Add Branch'
                              : 'Edit Branch Setting',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Color(0xff0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Update limits, order days, submit timing, area, type, and active status.',
                          style: TextStyle(
                            color: Color(0xff64748B),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _Input(
                            controller: _branch,
                            label: 'Branch Name',
                            icon: Icons.storefront_rounded,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _Input(
                            controller: _email,
                            label: 'Email',
                            icon: Icons.email_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _Input(
                            controller: _zone,
                            label: 'Zone',
                            icon: Icons.location_on_rounded,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _Input(
                            controller: _area,
                            label: 'Area',
                            icon: Icons.map_rounded,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _Input(
                            controller: _type,
                            label: 'Branch Type',
                            icon: Icons.account_tree_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _Input(
                            controller: _zoneManager,
                            label: 'Zone Manager',
                            icon: Icons.supervisor_account_rounded,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _Input(
                            controller: _zoneManagerEmail,
                            label: 'Zone Manager Email',
                            icon: Icons.alternate_email_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _SectionTitle(
                      icon: Icons.calendar_month_rounded,
                      title: 'Order Days',
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _days.map((day) {
                        final selected = _value.orderDays.contains(day);
                        return FilterChip(
                          selected: selected,
                          backgroundColor: Colors.white,

                          label: Text(day),
                          onSelected: (v) {
                            final next = [..._value.orderDays];
                            if (v) {
                              next.add(day);
                            } else {
                              next.remove(day);
                            }
                            setState(() {
                              _value = _value.copyWith(orderDays: next);
                            });
                          },
                          selectedColor: const Color(0xffDBEAFE),
                          checkmarkColor: const Color(0xff2563EB),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 22),
                    _SectionTitle(
                      icon: Icons.schedule_rounded,
                      title: 'Submit Window',
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _NumberInput(
                            controller: _start,
                            label: 'Start Hour',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _NumberInput(
                            controller: _end,
                            label: 'End Hour',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    _SectionTitle(icon: Icons.speed_rounded, title: 'Limits'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _NumberInput(
                            controller: _max,
                            label: 'Max Adj Limit',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _NumberInput(
                            controller: _increase,
                            label: 'Order Increase Limit',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _NumberInput(
                            controller: _edit,
                            label: 'Order Edit Limit',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _NumberInput(
                            controller: _additional,
                            label: 'Additional Limit',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    SwitchListTile(
                      value: _value.isActive,
                      onChanged: (v) {
                        setState(() {
                          _value = _value.copyWith(isActive: v);
                        });
                      },
                      activeThumbColor: AppColors.primaryColor,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: Color(0xffD8E5F3)),
                      ),
                      title: const Text(
                        'Active Branch',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: const Text(
                        'Turn off to hide this branch from active order flows.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 22),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: AppColors.secondaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Save Branch'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xff2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xff0EA5E9), size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xff0F172A),
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}

class _Input extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;

  const _Input({
    required this.controller,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: AppColors.backgroundWidget,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.primaryColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.primaryColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.primaryColor),
        ),
      ),
    );
  }
}

class _NumberInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const _NumberInput({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.backgroundWidget,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.primaryColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.primaryColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.primaryColor),
        ),
      ),
    );
  }
}
