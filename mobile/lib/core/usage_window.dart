// Ngày sử dụng và quy tắc Android cùng tính theo giờ Việt Nam (UTC+7).
DateTime usageLocalTime(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 7));

bool outsideUsageWindow(Map? rule, DateTime localTime) {
  if (rule?['isEnabled'] != true) return false;
  int? minutes(Object? value) {
    final parts = '$value'.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }
    return hour * 60 + minute;
  }

  final start = minutes(rule?['startTime']);
  final end = minutes(rule?['endTime']);
  if (start == null || end == null || start >= end) return false;
  final now = localTime.hour * 60 + localTime.minute;
  return now < start || now >= end;
}

String usageHeadline({
  required Map? rule,
  required DateTime localTime,
  required bool hasReport,
  required int remainingMinutes,
}) {
  if (outsideUsageWindow(rule, localTime)) return 'Đang trong giờ nghỉ';
  if (!hasReport) return 'Chưa có báo cáo';
  if (rule?['isEnabled'] != true) return 'Chưa bật giới hạn';
  return remainingMinutes <= 0
      ? 'Đã hết thời gian hôm nay'
      : 'Còn $remainingMinutes phút';
}
