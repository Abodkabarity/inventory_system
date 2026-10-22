import 'package:flutter/material.dart';

/// Builds a page on its first visit and keeps its State until this shell closes.
/// Hidden pages cannot animate or receive keyboard focus. Builders still receive
/// updated parent inputs (for example, a changed reporting date).
class RetainedPageStack<T> extends StatefulWidget {
  final List<T> pages;
  final T selectedPage;
  final Widget Function(BuildContext context, T page) pageBuilder;

  const RetainedPageStack({
    super.key,
    required this.pages,
    required this.selectedPage,
    required this.pageBuilder,
  });

  @override
  State<RetainedPageStack<T>> createState() => _RetainedPageStackState<T>();
}

class _RetainedPageStackState<T> extends State<RetainedPageStack<T>> {
  final _visited = <T>{};

  @override
  void initState() {
    super.initState();
    _visited.add(widget.selectedPage);
  }

  @override
  void didUpdateWidget(covariant RetainedPageStack<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visited.retainAll(widget.pages);
    _visited.add(widget.selectedPage);
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.pages.indexOf(widget.selectedPage);
    assert(index >= 0, 'The selected page must belong to this shell.');
    return IndexedStack(
      index: index,
      children: [
        for (final page in widget.pages)
          KeyedSubtree(
            key: ValueKey<T>(page),
            child: _visited.contains(page)
                ? ExcludeFocus(
                    excluding: page != widget.selectedPage,
                    child: TickerMode(
                      enabled: page == widget.selectedPage,
                      child: widget.pageBuilder(context, page),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
      ],
    );
  }
}
