import 'package:flutter/material.dart';
import '../services/notification_service.dart';

/// Screen to display user's notifications
class NotificationsScreen extends StatelessWidget {
  final VoidCallback? onBack;
  final Function(String screen, Map<String, dynamic> data)? onNotificationTap;

  const NotificationsScreen({
    super.key,
    this.onBack,
    this.onNotificationTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: onBack,
              )
            : null,
        title: const Text('Notifications'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'mark_all_read') {
                NotificationService.markAllAsRead();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All notifications marked as read')),
                );
              } else if (value == 'clear_old') {
                NotificationService.deleteOldNotifications();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Old notifications cleared')),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'mark_all_read',
                child: Row(
                  children: [
                    Icon(Icons.done_all, size: 20),
                    SizedBox(width: 8),
                    Text('Mark all as read'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear_old',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep, size: 20),
                    SizedBox(width: 8),
                    Text('Clear old notifications'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: NotificationService.getUserNotifications(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final notifications = snapshot.data ?? [];

          if (notifications.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              return _NotificationTile(
                notification: notifications[index],
                onTap: () {
                  final notif = notifications[index];
                  // Mark as read
                  NotificationService.markAsRead(notif['id']);
                  // Navigate
                  final data = notif['data'] as Map<String, dynamic>? ?? {};
                  final screen = data['screen'] as String? ?? '';
                  onNotificationTap?.call(screen, data);
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text(
            'No notifications yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'You\'ll see booking updates here',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

/// Individual notification tile
class _NotificationTile extends StatelessWidget {
  final Map<String, dynamic> notification;
  final VoidCallback? onTap;

  const _NotificationTile({
    required this.notification,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isRead = notification['read'] == true;
    final type = notification['type'] as String? ?? '';
    final title = notification['title'] as String? ?? '';
    final body = notification['body'] as String? ?? '';
    final createdAt = notification['createdAt'];

    return Container(
      color: isRead ? null : Theme.of(context).primaryColor.withValues(alpha: 0.05),
      child: ListTile(
        onTap: onTap,
        leading: _buildIcon(type),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(createdAt),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
        trailing: !isRead
            ? Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  shape: BoxShape.circle,
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildIcon(String type) {
    IconData icon;
    Color color;
    Color bgColor;

    switch (type) {
      case 'new_request':
        icon = Icons.notification_important;
        color = Colors.blue;
        bgColor = Colors.blue.shade50;
        break;
      case 'request_accepted':
        icon = Icons.check_circle;
        color = Colors.green;
        bgColor = Colors.green.shade50;
        break;
      case 'request_rejected':
        icon = Icons.cancel;
        color = Colors.red;
        bgColor = Colors.red.shade50;
        break;
      case 'booking_cancelled_by_chef':
      case 'booking_cancelled_by_customer':
        icon = Icons.event_busy;
        color = Colors.orange;
        bgColor = Colors.orange.shade50;
        break;
      case 'booking_completed':
        icon = Icons.star;
        color = Colors.amber;
        bgColor = Colors.amber.shade50;
        break;
      case 'chat_message':
        icon = Icons.chat_bubble;
        color = Colors.purple;
        bgColor = Colors.purple.shade50;
        break;
      default:
        icon = Icons.notifications;
        color = Colors.grey;
        bgColor = Colors.grey.shade100;
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '';

    final DateTime time;
    if (timestamp is DateTime) {
      time = timestamp;
    } else {
      time = (timestamp as dynamic).toDate();
    }

    final diff = DateTime.now().difference(time);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${time.day}/${time.month}/${time.year}';
  }
}

/// Notification bell widget with badge for unread count
class NotificationBell extends StatelessWidget {
  final VoidCallback? onTap;

  const NotificationBell({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: NotificationService.getUnreadCount(),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;

        return Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              onPressed: onTap,
            ),
            if (count > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

