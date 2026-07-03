import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_theme.dart';
import '../../core/date_utils_uae.dart';
import '../bloc/mobile_order_bloc.dart';
import '../widgets/brand_header.dart';

class BranchSelectPage extends StatefulWidget {
  const BranchSelectPage({super.key});

  @override
  State<BranchSelectPage> createState() => _BranchSelectPageState();
}

class _BranchSelectPageState extends State<BranchSelectPage> {
  final pickerController = TextEditingController();

  @override
  void dispose() {
    pickerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Refresh branches',
            onPressed: () =>
                context.read<MobileOrderBloc>().add(BranchesRequested()),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: () =>
                context.read<MobileOrderBloc>().add(LogoutRequested()),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: BlocBuilder<MobileOrderBloc, MobileOrderState>(
        builder: (context, state) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              BrandHeader(
                title: 'Choose Branch',
                subtitle: 'Operational order date: ${displayDate(state.date)}',
              ),
              const SizedBox(height: 22),
              _SelectionCard(state: state, pickerController: pickerController),
            ],
          );
        },
      ),
    );
  }
}

class _SelectionCard extends StatelessWidget {
  final MobileOrderState state;
  final TextEditingController pickerController;

  const _SelectionCard({required this.state, required this.pickerController});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Start preparing',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: AppTheme.navy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${state.branches.length} submitted branch(es) ready for this order date.',
              style: TextStyle(color: Colors.blueGrey.shade700),
            ),
            const SizedBox(height: 22),
            DropdownButtonFormField<String>(
              initialValue: state.selectedBranch.isEmpty
                  ? null
                  : state.selectedBranch,
              items: state.branches
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.name,
                      child: Text(e.name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  context.read<MobileOrderBloc>().add(BranchSelected(value));
                }
              },
              decoration: const InputDecoration(
                labelText: 'Branch',
                prefixIcon: Icon(Icons.storefront),
              ),
            ),
            const SizedBox(height: 14),
            if (state.pickerNames.isNotEmpty) ...[
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Prepared by',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.navy,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      pickerController.clear();
                      context.read<MobileOrderBloc>().add(
                        const PickerNameChanged(''),
                      );
                    },
                    icon: const Icon(Icons.person_add_alt_1, size: 18),
                    label: const Text('Add new person'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final name in state.pickerNames)
                    ChoiceChip(
                      selected:
                          name.toLowerCase() ==
                          state.pickerName.trim().toLowerCase(),
                      label: Text(name),
                      avatar: const Icon(Icons.badge_outlined, size: 18),
                      onSelected: (_) {
                        pickerController.text = name;
                        context.read<MobileOrderBloc>().add(
                          PickerNameChanged(name),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: pickerController,
              textCapitalization: TextCapitalization.words,
              onChanged: (value) {
                context.read<MobileOrderBloc>().add(PickerNameChanged(value));
              },
              decoration: const InputDecoration(
                labelText: 'Prepared by',
                hintText: 'Write employee name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              onPressed: state.canContinue
                  ? () => context.read<MobileOrderBloc>().add(OrderRequested())
                  : null,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Next'),
            ),
          ],
        ),
      ),
    );
  }
}
