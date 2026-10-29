import 'package:flutter_test/flutter_test.dart';
import 'package:nhombar/core/usage_window.dart';

void main() {
  final rule = {
    'isEnabled': true,
    'startTime': '07:00:00',
    'endTime': '21:00:00',
  };
  test('21:00 is rest time even with unused or approved bonus minutes', () {
    expect(
      usageHeadline(
        rule: rule,
        localTime: DateTime(2026, 10, 29, 21),
        hasReport: true,
        remainingMinutes: 53,
      ),
      'Đang trong giờ nghỉ',
    );
    expect(outsideUsageWindow(rule, DateTime(2026, 10, 29, 20, 59)), isFalse);
  });
  test('usage starts at 07:00 and remains unavailable before it', () {
    expect(outsideUsageWindow(rule, DateTime(2026, 10, 29, 6, 59)), isTrue);
    expect(outsideUsageWindow(rule, DateTime(2026, 10, 29, 7)), isFalse);
  });
  test(
    'exhausted allowance is distinct from available minutes and no report',
    () {
      final now = DateTime(2026, 10, 29, 12);
      expect(
        usageHeadline(
          rule: rule,
          localTime: now,
          hasReport: true,
          remainingMinutes: 0,
        ),
        'Đã hết thời gian hôm nay',
      );
      expect(
        usageHeadline(
          rule: rule,
          localTime: now,
          hasReport: true,
          remainingMinutes: 15,
        ),
        'Còn 15 phút',
      );
      expect(
        usageHeadline(
          rule: rule,
          localTime: now,
          hasReport: false,
          remainingMinutes: 0,
        ),
        'Chưa có báo cáo',
      );
    },
  );
  test('disabled or unavailable rules do not imply rest or a system lock', () {
    expect(
      outsideUsageWindow({
        ...rule,
        'isEnabled': false,
      }, DateTime(2026, 10, 29, 22)),
      isFalse,
    );
    expect(outsideUsageWindow(null, DateTime(2026, 10, 29, 22)), isFalse);
  });
  test('UTC is converted to the same usage day as native Vietnam policy', () {
    final local = usageLocalTime(DateTime.utc(2026, 10, 29, 14));
    expect(local.hour, 21);
    expect(outsideUsageWindow(rule, local), isTrue);
  });
}
