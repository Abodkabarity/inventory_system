import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/items_tracker_email.dart';
import '../../../domain/entities/items_tracker_record.dart';
import '../../../domain/repositories/items_tracker_repository.dart';

Future<void> showItemsTrackerEmailDialog({
  required BuildContext context,
  required ItemsTrackerRepository repository,
  required List<String> itemIds,
  String? company,
  Future<bool> Function(Uri)? outlookLauncher,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ItemsTrackerEmailDialog(
      repository: repository,
      itemIds: itemIds,
      company: company,
      outlookLauncher: outlookLauncher,
    ),
  );
}

/// Opening Outlook never counts as sending. The user confirms after pressing
/// Send in Outlook; draft reservations also survive closing this dialog.
class ItemsTrackerEmailDialog extends StatefulWidget {
  final ItemsTrackerRepository repository;
  final List<String> itemIds;
  final String? company;
  final Future<bool> Function(Uri)? outlookLauncher;
  const ItemsTrackerEmailDialog({
    super.key,
    required this.repository,
    required this.itemIds,
    this.company,
    this.outlookLauncher,
  });

  @override
  State<ItemsTrackerEmailDialog> createState() =>
      _ItemsTrackerEmailDialogState();
}

class _ItemsTrackerEmailDialogState extends State<ItemsTrackerEmailDialog> {
  static const _ink = Color(0xff19344a);
  static const _accent = AppColors.primaryColor;
  List<ItemsTrackerEmailDraft> _drafts = [];
  final _opened = <String>{};
  final _sent = <String>{};
  final _cancelled = <String>{};
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final drafts = await widget.repository.prepareEmails(
        widget.itemIds,
        company: widget.company,
      );
      if (!mounted) return;
      setState(() {
        _drafts = drafts;
        _opened.addAll(
          drafts
              .where((draft) => draft.openedAt != null)
              .map((draft) => draft.id),
        );
        _sent.addAll(
          drafts.where((draft) => draft.isSent).map((draft) => draft.id),
        );
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _errorText(error);
        });
      }
    }
  }

  Future<bool> _confirm(String title, String body, String label) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryColor,
              ),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Back'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(label),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _open(
    ItemsTrackerEmailDraft draft, {
    bool reopen = false,
  }) async {
    if (_busy || _sent.contains(draft.id) || _cancelled.contains(draft.id)) {
      return;
    }
    if (reopen &&
        !await _confirm(
          'Reopen Outlook draft?',
          'Check Outlook first. Reopening can create another unsent draft. Do this only if this email has not been sent.',
          'Reopen draft',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    var reserved = false;
    var handedOff = false;
    try {
      reserved = await widget.repository.openEmailDraft(
        draft.id,
        reopen: reopen,
      );
      if (!reserved) {
        await _prepare();
        if (mounted) {
          setState(() {
            _notice =
                'This draft was already opened. Check Outlook and confirm sending, or reopen it if it was not sent.';
          });
        }
        return;
      }
      // Long company emails can exceed Windows mailto limits. Copy the complete
      // body and open recipients/subject only, with an explicit paste instruction.
      final fullUri = draft.outlookUri();
      final copyBody = fullUri.toString().length > 1800;
      if (copyBody) await Clipboard.setData(ClipboardData(text: draft.body));
      final uri = copyBody ? draft.outlookUri(includeBody: false) : fullUri;
      handedOff =
          await (widget.outlookLauncher?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
      if (!handedOff) {
        throw StateError(
          'Could not open Outlook. Check your default email app and try again.',
        );
      }
      if (mounted) {
        setState(() {
          _opened.add(draft.id);
          _notice = copyBody
              ? 'Full email text copied. Paste it into Outlook, send, then confirm below.'
              : 'Email opened in Outlook. Send it there, then select Confirm sent below.';
        });
      }
    } catch (error) {
      if (reserved && !handedOff) {
        try {
          await widget.repository.releaseEmailDraft(draft.id);
        } catch (_) {
          /* Keep the reservation if server state cannot be verified. */
        }
      }
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markSent(ItemsTrackerEmailDraft draft) async {
    if (_busy || !_opened.contains(draft.id)) return;
    // The button explicitly records the user's confirmation, not mail delivery.
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.repository.confirmEmailSent(draft.id);
      if (mounted) {
        setState(() {
          _sent.add(draft.id);
          _notice =
              'Email marked as sent. Sending again is disabled for these products.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(ItemsTrackerEmailDraft draft) async {
    if (_busy ||
        !await _confirm(
          'Discard unsent draft?',
          'Only discard if you did not send this email. Delete any matching Outlook draft too. These products will become available for a new email.',
          'I did not send it',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.cancelEmailDraft(draft.id);
      if (mounted) setState(() => _cancelled.add(draft.id));
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 800),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 16),
              child: Row(
                children: [
                  const Icon(Icons.outgoing_mail, color: _accent),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Send email with Outlook',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '1. Open Outlook  ·  2. Send the email  ·  3. Confirm sent',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xff748494),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(
                        color: AppColors.primaryColor,
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.company != null)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 14),
                              child: Text(
                                'Each department receives its own email. Products already sent are excluded from new messages.',
                                style: TextStyle(color: _ink),
                              ),
                            ),
                          if (_error != null)
                            _banner(
                              _error!,
                              const Color(0xffa93232),
                              const Color(0xffffeeee),
                            ),
                          if (_notice != null)
                            _banner(_notice!, _accent, const Color(0xffeaf8f6)),
                          if (_drafts.isEmpty && _error != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.primaryColor,
                                ),
                                onPressed: _busy ? null : _prepare,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Try again'),
                              ),
                            ),
                          for (final draft in _drafts) _draftCard(draft),
                        ],
                      ),
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.secondaryColor,
                    ),
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: const Text(
                      'Close',
                      style: TextStyle(fontWeight: FontWeight.w700),
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

  Widget _banner(String text, Color color, Color background) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontWeight: FontWeight.w600),
    ),
  );

  Widget _draftCard(ItemsTrackerEmailDraft draft) {
    final sent = _sent.contains(draft.id);
    final opened = _opened.contains(draft.id);
    final cancelled = _cancelled.contains(draft.id);
    return Container(
      key: ValueKey('emailDraft:${draft.id}'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xffdce7ef)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${ItemsTrackerRoles.label(draft.followUpRole)} · ${draft.products.length} ${draft.products.length == 1 ? 'product' : 'products'}',
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              if (sent)
                const Text(
                  'Email sent ✓',
                  style: TextStyle(
                    color: Color(0xff199b69),
                    fontWeight: FontWeight.w700,
                  ),
                )
              else if (cancelled)
                const Text(
                  'Draft discarded',
                  style: TextStyle(color: Color(0xff748494)),
                )
              else if (opened)
                const Text(
                  'Awaiting confirmation',
                  style: TextStyle(
                    color: Color(0xffb37717),
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _address('To', draft.recipients.to),
          _address('Cc', draft.recipients.cc),
          const SizedBox(height: 12),
          Text(
            draft.subject,
            style: const TextStyle(color: _ink, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xfff5f8fb),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: SingleChildScrollView(
                child: SelectableText(
                  draft.body,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ),
            ),
          ),
          if (!sent && !cancelled) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                if (!opened)
                  FilledButton.icon(
                    key: ValueKey('openEmail:${draft.id}'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _busy ? null : () => _open(draft),
                    icon: const Icon(Icons.open_in_new, size: 17),
                    label: const Text('Open in Outlook'),
                  )
                else ...[
                  FilledButton.icon(
                    key: ValueKey('confirmEmail:${draft.id}'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _busy ? null : () => _markSent(draft),
                    icon: const Icon(Icons.mark_email_read_outlined, size: 18),
                    label: const Text('Confirm sent'),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryColor,
                      side: const BorderSide(color: AppColors.primaryColor),
                    ),
                    onPressed: _busy ? null : () => _open(draft, reopen: true),
                    child: const Text('Reopen unsent draft'),
                  ),
                ],
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.secondaryColor,
                  ),
                  onPressed: _busy
                      ? null
                      : () async {
                          await Clipboard.setData(
                            ClipboardData(text: draft.body),
                          );
                          if (mounted) {
                            setState(() => _notice = 'Email text copied.');
                          }
                        },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy text'),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.secondaryColor,
                  ),
                  onPressed: _busy ? null : () => _cancel(draft),
                  child: const Text('Discard unsent draft'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _address(String label, List<String> addresses) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 36,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xff748494),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            addresses.join('; '),
            style: const TextStyle(color: _ink, fontSize: 12),
          ),
        ),
      ],
    ),
  );

  String _errorText(Object error) {
    final text = error.toString();
    if (text.contains('SocketException') || text.contains('ClientException')) {
      return 'Connection unavailable. The email is not marked as sent. Please try again.';
    }
    return text.replaceFirst('Bad state: ', '');
  }
}
