import 'online_overview.dart';
import 'stock_management.dart';

const onlineAvailabilityRanks = [OnlineRank.a, OnlineRank.b, OnlineRank.c];

class OnlineRankAvailability {
  final OnlineRank rank;
  final int total, available, unknown;
  const OnlineRankAvailability({
    required this.rank,
    required this.total,
    required this.available,
    required this.unknown,
  });
  double? get percent => total == 0 ? null : available * 100 / total;
  int get withoutStock => total - available - unknown;
}

class OnlineBranchAvailability {
  final String branch;
  final Map<OnlineRank, OnlineRankAvailability> ranks;
  const OnlineBranchAvailability({required this.branch, required this.ranks});
}

class OnlineAvailabilitySnapshot {
  final String generation;
  final DateTime? stockDay;
  final List<OnlineBranchAvailability> branches;
  const OnlineAvailabilitySnapshot({
    required this.generation,
    required this.stockDay,
    required this.branches,
  });

  factory OnlineAvailabilitySnapshot.fromMap(
    Map<String, dynamic> data, {
    required String generation,
    required List<OnlineBranch> approvedBranches,
  }) {
    if (data['generation'] != generation || generation.isEmpty) {
      throw StateError('Online availability snapshot changed.');
    }
    final names = approvedBranches.map((branch) => branch.name).toSet();
    if (names.isEmpty || names.length != approvedBranches.length) {
      throw StateError('Invalid online branch list.');
    }
    int count(Object? value) {
      if (value is! num ||
          !value.isFinite ||
          value < 0 ||
          value != value.toInt()) {
        throw StateError('Invalid availability count.');
      }
      return value.toInt();
    }

    final totals = <OnlineRank, int>{};
    final grouped = <String, Map<OnlineRank, OnlineRankAvailability>>{};
    for (final raw in data['rows'] as List? ?? const []) {
      final row = stockMap(raw);
      final branch = '${row['branch_name']}';
      final rank = onlineAvailabilityRanks
          .where((rank) => rank.name == row['rank'])
          .firstOrNull;
      if (!names.contains(branch) || rank == null) {
        throw StateError('Availability contains an unapproved branch or rank.');
      }
      final total = count(row['total']);
      final available = count(row['available']);
      final unknown = count(row['unknown']);
      if (available + unknown > total ||
          (totals.containsKey(rank) && totals[rank] != total)) {
        throw StateError('Availability totals do not agree.');
      }
      totals[rank] = total;
      final group = grouped.putIfAbsent(branch, () => {});
      if (group.containsKey(rank)) {
        throw StateError('Duplicate availability row.');
      }
      group[rank] = OnlineRankAvailability(
        rank: rank,
        total: total,
        available: available,
        unknown: unknown,
      );
    }
    if (grouped.length != names.length ||
        grouped.values.any((ranks) => ranks.length != 3)) {
      throw StateError('Incomplete online availability.');
    }
    return OnlineAvailabilitySnapshot(
      generation: generation,
      stockDay: DateTime.tryParse('${data['stock_day']}'),
      branches: List.unmodifiable([
        for (final branch in approvedBranches)
          OnlineBranchAvailability(
            branch: branch.name,
            ranks: Map.unmodifiable(grouped[branch.name]!),
          ),
      ]),
    );
  }
}
