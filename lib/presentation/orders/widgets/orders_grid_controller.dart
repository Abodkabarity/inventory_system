import 'package:syncfusion_flutter_datagrid/datagrid.dart';

class OrdersGridController {
  final DataGridController controller = DataGridController();

  /// reference to the grid source
  DataGridSource? source;

  void attachSource(DataGridSource s) {
    source = s;
  }

  void clearAllGridFilters() {
    source?.clearFilters();
  }

  void clearSelection() {
    controller.selectedIndex = -1;
    controller.selectedRow = null;
  }

  void resetGridUi() {
    clearAllGridFilters();
    clearSelection();
  }
}
