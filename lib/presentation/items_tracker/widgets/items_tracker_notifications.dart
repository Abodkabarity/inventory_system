import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/items_tracker_record.dart';

Future<ItemsTrackerNotification?> showItemsTrackerNotificationsSheet({
  required BuildContext context,
  required List<ItemsTrackerNotification> notifications,
  required Future<void> Function() onMarkAllRead,
}) {
  return showModalBottomSheet<ItemsTrackerNotification>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _NotificationsSheet(
      notifications: notifications,
      onMarkAllRead: onMarkAllRead,
    ),
  );
}

class _NotificationsSheet extends StatefulWidget {
  final List<ItemsTrackerNotification> notifications;
  final Future<void> Function() onMarkAllRead;

  const _NotificationsSheet({
    required this.notifications,
    required this.onMarkAllRead,
  });

  @override
  State<_NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<_NotificationsSheet> {
  bool _markingAllRead = false;

  @override
  Widget build(BuildContext context) {
    final unread = widget.notifications.where((item) => item.isUnread).length;
    final maxHeight = MediaQuery.sizeOf(context).height * .78;
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: const BoxDecoration(
          color: Color(0xfff7fafc),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xffc7d5dc),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 16, 14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xffe3f2f5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.notifications_active_outlined,
                      color: Color(0xff16758a),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Notifications',
                          style: TextStyle(
                            color: Color(0xff183947),
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          unread == 0
                              ? 'You are all caught up'
                              : '$unread unread update${unread == 1 ? '' : 's'}',
                          style: const TextStyle(
                            color: Color(0xff718692),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (unread > 0)
                    TextButton(
                      onPressed: _markingAllRead
                          ? null
                          : () async {
                              final navigator = Navigator.of(context);
                              setState(() => _markingAllRead = true);
                              try {
                                await widget.onMarkAllRead();
                                if (mounted) navigator.pop();
                              } finally {
                                if (mounted) {
                                  setState(() => _markingAllRead = false);
                                }
                              }
                            },
                      child: _markingAllRead
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Mark all read'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xffdce6eb)),
            Expanded(
              child: widget.notifications.isEmpty
                  ? const _NotificationsEmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 26),
                      itemCount: widget.notifications.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 9),
                      itemBuilder: (context, index) => _NotificationTile(
                        notification: widget.notifications[index],
                        onTap: () =>
                            Navigator.pop(context, widget.notifications[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final ItemsTrackerNotification notification;
  final VoidCallback onTap;

  const _NotificationTile({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isUnread = notification.isUnread;
    final color = _activityColor(notification.activityType);
    final preview = notification.preview.trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isUnread ? const Color(0xffeaf7fa) : Colors.white,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: isUnread
                  ? const Color(0xffa9dce5)
                  : const Color(0xffe0e8ec),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  _activityIcon(notification.activityType),
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: const Color(0xff1d3c49),
                              fontWeight: isUnread
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                        if (isUnread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 8),
                            decoration: const BoxDecoration(
                              color: Color(0xff168aa2),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${notification.itemCode} · ${notification.itemName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xff37707e),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xff657984),
                          fontSize: 12.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      _timeAgo(notification.createdAt),
                      style: const TextStyle(
                        color: Color(0xff8a9aa2),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: Color(0xff8ea3ad)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationsEmptyState extends StatelessWidget {
  const _NotificationsEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: const Color(0xffe7f3f5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              color: Color(0xff30788a),
              size: 31,
            ),
          ),
          const SizedBox(height: 13),
          const Text(
            'No notifications yet',
            style: TextStyle(
              color: Color(0xff284654),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'New tracker activity will appear here.',
            style: TextStyle(color: Color(0xff7d9099), fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

IconData _activityIcon(String type) => switch (type) {
  'comment' => Icons.chat_bubble_outline_rounded,
  'action' => Icons.bolt_rounded,
  'follow_up' => Icons.assignment_return_outlined,
  'file_uploaded' => Icons.attach_file_rounded,
  'status_change' => Icons.sync_alt_rounded,
  'created' => Icons.playlist_add_rounded,
  _ => Icons.edit_outlined,
};

Color _activityColor(String type) => switch (type) {
  'comment' => const Color(0xff287ea5),
  'action' => const Color(0xffb46a13),
  'follow_up' => const Color(0xff7651a5),
  'file_uploaded' => const Color(0xff168873),
  'status_change' => const Color(0xffbe5c35),
  'created' => const Color(0xff168873),
  _ => const Color(0xff547480),
};

String _timeAgo(DateTime value) {
  final difference = DateTime.now().difference(value.toLocal());
  if (difference.inMinutes < 1) return 'Just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
  if (difference.inHours < 24) return '${difference.inHours}h ago';
  if (difference.inDays < 7) return '${difference.inDays}d ago';
  return DateFormat('dd MMM, h:mm a').format(value.toLocal());
}
