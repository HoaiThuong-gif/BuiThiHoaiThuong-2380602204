import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'extra_english.dart';

final appLocale = ValueNotifier<Locale>(const Locale('vi'));
Future<void> changeLanguage(String code) async {
  appLocale.value = Locale(code);
  await (await SharedPreferences.getInstance()).setString('language', code);
  try {
    await const MethodChannel('vn.nhombar/device')
        .invokeMethod('language', {'code': code});
  } on MissingPluginException {
    /* Widget previews. */
  }
}

String tr(BuildContext context, String text) {
  if (Localizations.localeOf(context).languageCode != 'en') return text;
  if (_english[text] != null) return _english[text]!;
  if (extraEnglish[text] != null) return extraEnglish[text]!;
  if (text.contains('\n')) {
    return text.split('\n').map((line) => tr(context, line)).join('\n');
  }
  final patterns = <RegExp, String Function(Match)>{
    RegExp(r'^Trung bình: (.+) dB$'): (m) => 'Average: ${m[1]} dB',
    RegExp(r'^Cao nhất: (.+) dB$'): (m) => 'Highest: ${m[1]} dB',
    RegExp(r'^Đã dùng (\d+) phút · Còn (\d+) phút$'): (m) =>
        'Used ${m[1]} minutes · ${m[2]} minutes left',
    RegExp(r'^Thêm (\d+) phút · (.+)$'): (m) =>
        '${m[1]} more minutes · ${tr(context, m[2]!)}',
    RegExp(r'^Con xin thêm (\d+) phút$'): (m) =>
        'Your child is asking for ${m[1]} more minutes',
    RegExp(r'^(\d+) phút mỗi ngày$'): (m) => '${m[1]} minutes per day',
    RegExp(r'^Từ (.+) đến (.+)$'): (m) => 'From ${m[1]} to ${m[2]}',
    RegExp(r'^Giọng tiếng Việt (\d+)(.*)$'): (m) =>
        'Vietnamese voice ${m[1]}${m[2]!.isEmpty ? '' : ' (internet required)'}',
    RegExp(r'^Đã kết nối: (.+)$'): (m) => 'Connected: ${m[1]}',
    RegExp(r'^Lần cập nhật gần nhất: (.+)$'): (m) => 'Last update: ${m[1]}',
    RegExp(r'^Mã dùng một lần, hết hạn lúc (.+)\.$'): (m) =>
        'One-time code, expires at ${m[1]}.',
    RegExp(r'^(\d+) yêu cầu đang chờ$'): (m) => '${m[1]} requests waiting',
    RegExp(r'^Vừa kết nối(.*)$'): (m) =>
        'Recently connected${m[1]!.replaceAll(' · Lần gần nhất: đã khóa', ' · Last reported: locked')}',
    RegExp(r'^Chưa kết nối gần đây(.*)$'): (m) =>
        'Not connected recently${m[1]!.replaceAll(' · Lần gần nhất: đã khóa', ' · Last reported: locked')}',
    RegExp(r'^Xin chào, (.+)$'): (m) => 'Hello, ${m[1]}',
    RegExp(r'^Chào con, (.+)!$'): (m) => 'Hi, ${m[1]}!',
    RegExp(r'^Còn (\d+) phút$'): (m) => '${m[1]} minutes left',
    RegExp(r'^(\d+) phút$'): (m) => '${m[1]} minutes',
    RegExp(r'^Đã dùng (\d+) phút · Giới hạn (\d+) phút$'): (m) =>
        'Used ${m[1]} minutes · Limit ${m[2]} minutes',
    RegExp(r'^Báo cáo gần nhất: (.+)$'): (m) => 'Last report: ${m[1]}',
    RegExp(r'^Cập nhật: (.+)$'): (m) => 'Updated: ${m[1]}',
    RegExp(r'^Trong vòng (\d+) m$'): (m) => 'Within ${m[1]} m',
    RegExp(r'^Độ chính xác khoảng (\d+) m$'): (m) =>
        'Accuracy: about ${m[1]} m',
    RegExp(
      r'^Nhập mã gồm 6 số được gửi đến (.+)\. Mã có hiệu lực trong 5 phút\.$',
    ): (m) =>
        'Enter the 6-digit code sent to ${m[1]}. It expires in 5 minutes.',
  };
  for (final e in patterns.entries) {
    final match = e.key.firstMatch(text);
    if (match != null) return e.value(match);
  }
  return text;
}

class AppText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  const AppText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
  });
  @override
  Widget build(BuildContext context) => Text(
    tr(context, data),
    style: style,
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: overflow,
    softWrap: softWrap,
  );
}

const _english = <String, String>{
  'Tổng quan': 'Overview',
  'Vị trí': 'Location',
  'Quản lý': 'Manage',
  'Tài khoản': 'Account',
  'Hôm nay': 'Today',
  'Điện thoại': 'Phone',
  'Thông báo': 'Notifications',
  'Cá nhân': 'Profile',
  'Cài đặt': 'Settings',
  'Đăng nhập': 'Sign in',
  'Đăng ký': 'Sign up',
  'Đăng xuất': 'Sign out',
  'Họ và tên': 'Full name',
  'Mật khẩu': 'Password',
  'Email': 'Email',
  'Mật khẩu mới': 'New password',
  'Mật khẩu hiện tại': 'Current password',
  'Cùng con tạo thói quen dùng điện thoại lành mạnh.':
      'Help your child build healthy phone habits.',
  'Chào mừng bạn trở lại': 'Welcome back',
  'Tạo tài khoản phụ huynh': 'Create a parent account',
  'Kiểm tra email của bạn': 'Check your email',
  'Lấy lại mật khẩu': 'Reset your password',
  'Mã xác nhận': 'Verification code',
  'Gửi lại mã': 'Send a new code',
  'Xác nhận': 'Confirm',
  'Gửi mã xác nhận': 'Send code',
  'Tạo tài khoản': 'Create account',
  'Quay lại đăng nhập': 'Back to sign in',
  'Đã có tài khoản? Đăng nhập': 'Already registered? Sign in',
  'Chưa có tài khoản? Đăng ký': 'New here? Sign up',
  'Quên mật khẩu?': 'Forgot your password?',
  'Hiện mật khẩu': 'Show password',
  'Ẩn mật khẩu': 'Hide password',
  'Ít nhất 10 ký tự, gồm chữ hoa, chữ thường, số và ký tự đặc biệt.': 'At least 10 characters, with uppercase and lowercase letters, a number and a symbol.',
  'Vui lòng nhập đúng email.': 'Enter a valid email address.',
  'Vui lòng nhập mật khẩu.': 'Enter your password.',
  'Vui lòng nhập họ tên.': 'Enter your full name.',
  'Vui lòng nhập đủ 6 số.': 'Enter all 6 digits.',
  'Mật khẩu cần ít nhất 10 ký tự.': 'Use at least 10 characters.',
  'Lưu': 'Save',
  'Hủy': 'Cancel',
  'Giữ lại': 'Keep',
  'Đồng ý': 'Allow',
  'Đóng': 'Close',
  'Đã hiểu': 'Got it',
  'Thử lại': 'Try again',
  'Đang lưu…': 'Saving…',
  'Đang gửi…': 'Sending…',
  'Quản trị viên': 'Administrator',
  'Phụ huynh': 'Parent',
  'Con': 'Child',
  'Quản lý NhomBar': 'Manage NhomBar',
  'Tổng tài khoản': 'Total accounts',
  'Hồ sơ con': 'Child profiles',
  'Tài khoản đang hoạt động': 'Active accounts',
  'Thông tin vị trí của trẻ được dành cho gia đình.':
      'Children’s location information is only available to their families.',
  'Thêm tài khoản': 'Add account',
  'Sửa tài khoản': 'Edit account',
  'Loại tài khoản': 'Account type',
  'Ngừng tài khoản': 'Deactivate account',
  'Ngừng tài khoản?': 'Deactivate this account?',
  'Người này sẽ không thể đăng nhập cho đến khi được mở lại.':
      'This person cannot sign in until the account is reactivated.',
  'Trạng thái tài khoản': 'Account status',
  'Đang hoạt động': 'Active',
  'Tạm ngừng': 'Inactive',
  'Đã ngừng': 'Inactive',
  'Mật khẩu ban đầu': 'Initial password',
  'Mật khẩu mới (bỏ trống để giữ nguyên)': 'New password (leave blank to keep)',
  'Gửi thông báo': 'Send notification',
  'Sửa thông báo': 'Edit notification',
  'Chọn người nhận': 'Choose recipient',
  'Tiêu đề': 'Title',
  'Nội dung': 'Message',
  'Xóa thông báo': 'Delete notification',
  'Xóa thông báo?': 'Delete this notification?',
  'Thông báo sẽ được xóa khỏi danh sách người nhận.':
      'The notification will be removed from the recipient’s list.',
  'Chưa có thông báo': 'No notifications yet',
  'Thông tin mới sẽ được hiển thị ở đây.': 'Updates will appear here.',
  'Bạn có thể gửi thông báo cho một tài khoản.':
      'Send a notification to an account.',
  'Thêm hồ sơ con': 'Add a child',
  'Tên của con': 'Child’s name',
  'Ngày sinh': 'Date of birth',
  'Chưa có hồ sơ của con': 'No child profiles yet',
  'Thêm hồ sơ để bắt đầu đồng hành cùng con.':
      'Add a profile to start supporting your child.',
  'Chưa có hồ sơ kết nối': 'No connected profile',
  'Nhờ bố mẹ kiểm tra lại tài khoản của con nhé.':
      'Ask your parents to check your account.',
  'Cùng con cân bằng học tập, vui chơi và nghỉ ngơi.':
      'Help your child balance learning, play and rest.',
  'Cùng xem hôm nay con còn bao nhiêu thời gian nhé.':
      'Let’s see how much phone time you have left today.',
  'Xem vị trí con chia sẻ': 'View shared location',
  'Thời gian, điện thoại và yêu cầu của con':
      'Time limits, phones and requests',
  'Xem thời gian sử dụng hôm nay': 'View today’s phone use',
  'Thời gian hôm nay': 'Today’s phone time',
  'Thời gian của con': 'Your phone time',
  'Chưa có báo cáo': 'No report yet',
  'Chưa bật giới hạn': 'No limit enabled',
  'Kết nối điện thoại của con để nhận thời gian sử dụng thực tế.':
      'Connect your child’s phone to receive actual usage reports.',
  'Chưa kết nối điện thoại.': 'No phone connected.',
  'Kết nối điện thoại của con': 'Connect your child’s phone',
  'Thời gian trong tuần': 'This week’s phone use',
  'Ứng dụng dùng nhiều trong tuần': 'Most used apps this week',
  'Chưa có thông tin sử dụng ứng dụng.': 'No app usage information yet.',
  'Xin thêm thời gian': 'Ask for more time',
  'Số phút muốn xin thêm': 'How many more minutes?',
  'Con muốn dùng thêm để làm gì?': 'What would you like more time for?',
  'Gửi bố mẹ': 'Send to parents',
  'Chưa có yêu cầu nào.': 'No requests yet.',
  'Chờ bố mẹ trả lời': 'Waiting for parents',
  'Đã đồng ý': 'Approved',
  'Chưa đồng ý': 'Declined',
  'Trả lời con': 'Reply to your child',
  'Lời nhắn cho con': 'Message to your child',
  'Con đang an toàn': 'I’m safe',
  'Con cần giúp đỡ?': 'Do you need help?',
  'Nhờ bố mẹ giúp đỡ': 'Ask parents for help',
  'Liên hệ bố mẹ': 'Contact parents',
  'Chưa thêm số điện thoại': 'No phone number added',
  'Đo tiếng ồn': 'Measure noise',
  'Thời gian được sử dụng': 'Allowed phone time',
  'Đổi thời gian sử dụng': 'Change phone time',
  'Tắt giới hạn': 'Turn off limits',
  'Tài khoản của con': 'Child’s account',
  'Tạo tài khoản cho con': 'Create a child account',
  'Email của con': 'Child’s email',
  'Tạo tài khoản riêng để con đăng nhập trên điện thoại của mình.':
      'Create a separate account for your child’s phone.',
  'Đã thiết lập quản lý điện thoại': 'Phone management is set up',
  'Chưa hoàn tất thiết lập khóa điện thoại':
      'Phone locking has not been set up',
  'Cho con dùng thêm': 'Allow more time',
  'Số phút cho phép': 'Minutes allowed',
  'Chuẩn bị mã mở khóa khi mất mạng': 'Prepare an offline unlock code',
  'Xác nhận tạo mã dự phòng': 'Confirm offline code setup',
  'Giữ mã này riêng cho bố mẹ': 'Keep this code private',
  'Đã lưu mã': 'I saved the code',
  'Kết thúc quản lý điện thoại': 'End phone management',
  'Ngắt kết nối điện thoại': 'Disconnect phone',
  'Ngắt kết nối': 'Disconnect',
  'Ngắt kết nối?': 'Disconnect this phone?',
  'Hồ sơ của con': 'Child’s profile',
  'Sửa hồ sơ con': 'Edit child profile',
  'Sửa hồ sơ': 'Edit profile',
  'Xóa hồ sơ con': 'Delete child profile',
  'Xóa hồ sơ': 'Delete profile',
  'Xóa hồ sơ của con?': 'Delete this child’s profile?',
  'Chưa có vị trí': 'No location yet',
  'Vị trí sẽ xuất hiện khi con cho phép và gửi từ điện thoại của mình.':
      'Location appears after your child agrees to share it from their phone.',
  'Vị trí được chia sẻ gần nhất': 'Last shared location',
  'Khu vực an toàn': 'Safe places',
  'Chưa thêm khu vực an toàn.': 'No safe places yet.',
  'Nhấn giữ trên bản đồ để chọn nhà, trường học hoặc nơi quen thuộc.': 'Touch and hold the map to choose home, school or another familiar place.',
  'Các lần chia sẻ gần đây': 'Recent location updates',
  'Thêm khu vực an toàn': 'Add a safe place',
  'Sửa khu vực an toàn': 'Edit safe place',
  'Tên địa điểm': 'Place name',
  'Khoảng cách quanh địa điểm (m)': 'Distance around this place (m)',
  'Xóa địa điểm': 'Delete place',
  'Xóa khu vực an toàn?': 'Delete this safe place?',
  'Thời gian sử dụng': 'Phone time',
  'Chọn thời gian phù hợp với việc học và nghỉ ngơi của con.':
      'Choose times that fit your child’s learning and rest.',
  'Số phút mỗi ngày': 'Minutes per day',
  'Được dùng từ': 'Available from',
  'Nghỉ từ': 'Rest from',
  'Cho con xin thêm thời gian': 'Let your child request more time',
  'Chỉ tăng thời gian sau khi bố mẹ đồng ý.':
      'Time is added only after a parent approves.',
  'Khóa điện thoại khi hết giờ': 'Lock the phone when time runs out',
  'Cần hoàn tất thiết lập quản lý trên điện thoại của con.':
      'Phone management must be set up on your child’s phone.',
  'Lưu thời gian': 'Save phone time',
  'Mã phụ huynh': 'Parent code',
  'Mã phụ huynh gồm 6 số': '6-digit parent code',
  'Thông tin cá nhân': 'Personal information',
  'Số điện thoại liên hệ': 'Contact phone number',
  'Đặt hoặc đổi mã phụ huynh': 'Set or change parent code',
  'Mã gồm 6 số dùng để xác nhận thay đổi quan trọng.':
      'Use a 6-digit code to confirm important changes.',
  'Mã hiện tại (bỏ trống nếu chưa đặt)':
      'Current code (leave blank if not set)',
  'Mã mới gồm 6 số': 'New 6-digit code',
  'Đổi mật khẩu': 'Change password',
  'Lịch sử quản lý': 'Management history',
  'Thông tin được chia sẻ': 'Shared information',
  'Cả nhà cùng biết': 'What the family shares',
  'Ngôn ngữ / Language': 'Language / Ngôn ngữ',
  'Điện thoại của con': 'Your phone',
  'Kết nối với bố mẹ': 'Connect with parents',
  'Điện thoại chưa được kết nối.': 'This phone is not connected.',
  'Quét mã kết nối': 'Scan connection code',
  'Mở phần cấp quyền': 'Open permission settings',
  'Bật cập nhật và lời nhắc': 'Enable updates and reminders',
  'Chia sẻ vị trí': 'Share location',
  'Chia sẻ vị trí bây giờ': 'Share location now',
  'Tiếp tục chia sẻ khi đóng ứng dụng': 'Keep sharing when the app is closed',
  'Khóa khi hết giờ': 'Lock when time runs out',
  'Xem hướng dẫn': 'View instructions',
  'Nhờ bố mẹ thiết lập': 'Ask a parent to set up',
  'Quét mã từ điện thoại bố mẹ': 'Scan the code on a parent’s phone',
  'Đang đo tiếng ồn': 'Measuring noise',
  'Đã dừng đo': 'Measurement stopped',
  'Kết quả đo': 'Results',
  'Bắt đầu đo': 'Start measuring',
  'Dừng đo': 'Stop measuring',
  'Gửi kết quả cho bố mẹ': 'Send results to parents',
  'Kết quả chỉ để tham khảo, có thể khác giữa các điện thoại. NhomBar không ghi âm và không lưu nội dung trò chuyện.': 'Results are approximate and vary between phones. NhomBar does not record or store conversations.',
  'Ứng dụng chưa sẵn sàng kết nối. Vui lòng liên hệ người cung cấp ứng dụng để được hỗ trợ.': 'The app is not ready to connect. Please contact the app provider for help.',
};
