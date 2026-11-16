import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/repositories/inventory_repository.dart';

const _ink = Color(0xFF17354D);
const _muted = Color(0xFF536A7D);
const _teal = Color(0xFF0C6F73);
const _mint = Color(0xFFE4F4F0);
const _border = Color(0xFFDEE8EF);

class InventoryDailyOrderExports extends StatefulWidget {
  const InventoryDailyOrderExports({super.key, required this.repository});

  final InventoryRepository repository;

  @override
  State<InventoryDailyOrderExports> createState() =>
      _InventoryDailyOrderExportsState();
}

class _InventoryDailyOrderExportsState
    extends State<InventoryDailyOrderExports> {
  late Future<List<String>> _dates;
  final _scrollController = ScrollController();
  String? _downloading;
  bool _downloadFailed = false;

  @override
  void initState() {
    super.initState();
    _dates = widget.repository.fetchDailyOrderExportDates();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _download(String date) async {
    if (_downloading != null) return;
    final route = ModalRoute.of(context);
    setState(() {
      _downloading = date;
      _downloadFailed = false;
    });
    try {
      final url = await widget.repository.fetchDailyOrderExportFileUrl(
        runDate: date,
      );
      if (!mounted || route?.isActive == false) return;
      if (url == null ||
          !await launchUrl(
            Uri.parse(url),
            mode: LaunchMode.externalApplication,
            webOnlyWindowName: '_self',
          )) {
        throw StateError('Export download could not start.');
      }
      if (!mounted) return;
      if (route?.isCurrent == true) {
        Navigator.of(context).pop();
      } else {
        setState(() => _downloading = null);
      }
    } catch (error) {
      if (!mounted) return;
      debugPrint('Daily Order export download: ${error.runtimeType}');
      setState(() {
        _downloading = null;
        _downloadFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      constraints: const BoxConstraints(maxWidth: 508, maxHeight: 570),
      backgroundColor: const Color(0xFFF5F8FC),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 508,
        child: Column(
          children: [
            const _ExportsHeader(),
            Expanded(
              child: FutureBuilder<List<String>>(
                future: _dates,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: _teal,
                        strokeWidth: 2.5,
                        semanticsLabel: 'Loading exports',
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return _ExportMessage(
                      icon: Icons.cloud_off_outlined,
                      message: 'Couldn’t load exports',
                      action: OutlinedButton.icon(
                        onPressed: () => setState(() {
                          _dates = widget.repository
                              .fetchDailyOrderExportDates();
                        }),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Retry'),
                      ),
                    );
                  }
                  final dates = snapshot.data ?? const [];
                  if (dates.isEmpty) {
                    return const _ExportMessage(
                      icon: Icons.folder_open_outlined,
                      message: 'No exports available',
                    );
                  }
                  return _buildFiles(dates);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiles(List<String> dates) {
    final count = NumberFormat.decimalPattern('en_US').format(dates.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
          child: Text(
            '$count Excel ${dates.length == 1 ? 'export' : 'exports'}',
            style: const TextStyle(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (_downloadFailed)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: _DownloadError(),
          ),
        Expanded(
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: ListView.separated(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: dates.length,
                separatorBuilder: (context, index) => const SizedBox(height: 7),
                itemBuilder: (context, index) {
                  final date = dates[index];
                  return _ExportRow(
                    date: date,
                    downloading: _downloading == date,
                    onDownload: _downloading == null
                        ? () => _download(date)
                        : null,
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExportsHeader extends StatelessWidget {
  const _ExportsHeader();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF142A46), Color(0xFF16415A), Color(0xFF12676B)],
          stops: [0, .62, 1],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0x2675DEC9),
                border: Border.all(color: const Color(0x4075DEC9)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.file_download_outlined,
                size: 23,
                color: Color(0xFF9DE6D7),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Semantics(
                header: true,
                child: const Text(
                  'Daily Order exports',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Close exports',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, size: 20),
              style: IconButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0x20FFFFFF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportRow extends StatelessWidget {
  const _ExportRow({
    required this.date,
    required this.downloading,
    required this.onDownload,
  });

  final String date;
  final bool downloading;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final parsed = DateTime.tryParse(date);
    final dateLabel = parsed == null
        ? date
        : DateFormat('d MMM yyyy', 'en_US').format(parsed);
    final weekday = parsed == null
        ? null
        : DateFormat('EEEE', 'en_US').format(parsed);
    final description = downloading
        ? 'Preparing download for $dateLabel'
        : 'Download export for $dateLabel';
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(13),
      side: const BorderSide(color: _border),
    );
    final icon = downloading
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: _teal),
          )
        : const Icon(Icons.download_rounded, size: 18);

    return Material(
      color: Colors.white,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onDownload,
        excludeFromSemantics: true,
        canRequestFocus: false,
        hoverColor: const Color(0xFFF0F8F7),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                if (constraints.maxWidth >= 230) ...[
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _mint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.calendar_today_outlined,
                      size: 17,
                      color: _teal,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dateLabel,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (weekday != null)
                        Text(
                          weekday,
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (constraints.maxWidth >= 365)
                  Tooltip(
                    message: description,
                    child: FilledButton.tonalIcon(
                      onPressed: onDownload,
                      style: FilledButton.styleFrom(
                        backgroundColor: _mint,
                        foregroundColor: _teal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: const Size(0, 36),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      icon: icon,
                      label: Text(downloading ? 'Preparing…' : 'Download'),
                    ),
                  )
                else
                  IconButton(
                    tooltip: description,
                    onPressed: onDownload,
                    style: IconButton.styleFrom(
                      foregroundColor: _teal,
                      backgroundColor: _mint,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: icon,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExportMessage extends StatelessWidget {
  const _ExportMessage({
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 31, color: _teal),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _ink, fontWeight: FontWeight.w700),
            ),
            if (action case final button?) ...[
              const SizedBox(height: 9),
              button,
            ],
          ],
        ),
      ),
    );
  }
}

class _DownloadError extends StatelessWidget {
  const _DownloadError();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1EB),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
          'Couldn’t start the download. Try again.',
          style: TextStyle(color: Color(0xFF8C3D2D), fontSize: 12),
        ),
      ),
    );
  }
}
