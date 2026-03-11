import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/store_bloc.dart';
import '../bloc/store_event.dart';

class BranchGrid extends StatelessWidget {
  final List<String> branches;
  final List<String> submitted;
  final String? selectedBranch;

  const BranchGrid({
    super.key,
    required this.branches,
    required this.submitted,
    required this.selectedBranch,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            "Branches Ordering Today",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),

        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),

            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 2.8,
            ),

            itemCount: branches.length,

            itemBuilder: (context, i) {
              final branch = branches[i];

              final isSubmitted = submitted.contains(branch);
              final isSelected = selectedBranch == branch;

              return GestureDetector(
                onTap: () {
                  context.read<StoreBloc>().add(SelectBranch(branch));
                },

                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),

                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),

                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xff1DB954) : Colors.white,

                    borderRadius: BorderRadius.circular(14),

                    border: Border.all(
                      color: isSelected ? Colors.green : Colors.grey.shade200,
                      width: isSelected ? 2 : 1,
                    ),

                    boxShadow: [
                      BoxShadow(
                        blurRadius: 12,
                        color: Colors.black.withOpacity(.06),
                      ),
                    ],
                  ),

                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: isSelected
                            ? Colors.white
                            : Colors.blue.shade50,
                        child: Icon(
                          isSubmitted ? Icons.check : Icons.store,
                          size: 18,
                          color: isSelected ? Colors.green : Colors.blue,
                        ),
                      ),

                      const SizedBox(width: 10),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              branch,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isSelected ? Colors.white : Colors.black,
                              ),
                            ),

                            const SizedBox(height: 4),

                            Text(
                              isSubmitted ? "Submitted" : "Not Submitted Yet",
                              style: TextStyle(
                                fontSize: 11,
                                color: isSelected
                                    ? Colors.white70
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (isSubmitted)
                        Icon(
                          Icons.check_circle,
                          color: isSelected ? Colors.white : Colors.green,
                          size: 18,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
