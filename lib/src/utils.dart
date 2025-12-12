import 'package:time/time.dart';

export 'utils/week.dart';

extension DateTimeRrule on DateTime {
  DateTime copyWith({
    int? year,
    int? month,
    int? day,
    int? hour,
    int? minute,
    int? second,
    int? millisecond,
    int? microsecond,
    bool? isUtc,
  }) {
    return InternalDateTimeRrule.create(
      year: year ?? this.year,
      month: month ?? this.month,
      day: day ?? this.day,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      second: second ?? this.second,
      millisecond: millisecond ?? this.millisecond,
      microsecond: microsecond ?? this.microsecond,
      isUtc: isUtc ?? this.isUtc,
    );
  }
}

extension InternalDateTimeRrule on DateTime {
  static DateTime create({
    required int year,
    int month = 1,
    int day = 1,
    int hour = 0,
    int minute = 0,
    int second = 0,
    int millisecond = 0,
    int microsecond = 0,
    bool isUtc = true,
  }) {
    final constructor = isUtc ? DateTime.utc : DateTime.new;
    return constructor(
      year,
      month,
      day,
      hour,
      minute,
      second,
      millisecond,
      microsecond,
    );
  }

  static DateTime date(int year, [int month = 1, int day = 1]) {
    final date = DateTime.utc(year, month, day);
    assert(date.isValidRruleDate);
    return date;
  }

  bool operator <(DateTime other) => isBefore(other);
  bool operator <=(DateTime other) =>
      isBefore(other) || isAtSameMomentAs(other);
  bool operator >(DateTime other) => isAfter(other);
  bool operator >=(DateTime other) => isAfter(other) || isAtSameMomentAs(other);

  DateTime get atStartOfDay => DateTimeRrule(this)
      .copyWith(hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);
  bool get isAtStartOfDay => this == atStartOfDay;
}

extension NullableDateTimeRrule on DateTime? {
  bool get isValidRruleDateTime => this == null || this!.isUtc;
  bool get isValidRruleDate =>
      isValidRruleDateTime && (this == null || this!.isAtStartOfDay);
}

extension NullableDurationRrule on Duration? {
  bool get isValidRruleTimeOfDay =>
      this == null || (0.days <= this! && this! <= 1.days);
}

extension IntRange on int {
  // Copied from supercharged_dart

  /// Creates an [Iterable<int>] that contains all values from current integer
  /// until (including) the value [n].
  ///
  /// Example:
  /// ```dart
  /// 0.rangeTo(5); // [0, 1, 2, 3, 4, 5]
  /// 3.rangeTo(1); // [3, 2, 1]
  /// ```
  Iterable<int> rangeTo(int n) {
    final count = (n - this).abs() + 1;
    final direction = (n - this).sign;
    var i = this - direction;
    return Iterable.generate(count, (index) {
      return i += direction;
    });
  }

  /// Creates an [Iterable<int>] that contains all values from current integer
  /// until (excluding) the value [n].
  ///
  /// Example:
  /// ```dart
  /// 0.until(5); // [0, 1, 2, 3, 4]
  /// 3.until(1); // [3, 2]
  /// ```
  Iterable<int> until(int n) {
    if (this < n) {
      return rangeTo(n - 1);
    } else if (this > n) {
      return rangeTo(n + 1);
    } else {
      return const Iterable.empty();
    }
  }
}

extension NullableIntRrule on int? {
  bool get isValidRruleDayOfWeek =>
      this == null || (DateTime.monday <= this! && this! <= DateTime.sunday);
}
