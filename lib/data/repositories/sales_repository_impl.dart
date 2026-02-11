import '../../domain/repositories/sales_repository.dart';
import '../datasources/remote/sales_remote_ds.dart';

class SalesRepositoryImpl implements SalesRepository {
  final SalesRemoteDs remote;
  const SalesRepositoryImpl(this.remote);

  num _to2(num v) => num.parse(v.toStringAsFixed(2));

  @override
  Future<Map<String, num>> fetchDemand30ByItemCode({
    required String branchName,
  }) async {
    final sums = await remote.fetchSumQtyByItemCode(branchName: branchName);

    final out = <String, num>{};
    for (final e in sums.entries) {
      final v = (e.value / 45) * 30;
      out[e.key] = _to2(v);
    }
    return out;
  }
}
