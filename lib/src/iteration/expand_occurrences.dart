import 'dart:math';

import 'package:collection/collection.dart';
import 'package:time/time.dart';

import '../../rrule.dart';
import '../utils.dart';

Iterable<DateTime> expandOccurrences({
  required RecurrenceRule rule,
  required DateTime dtStart,
  required DateTime before,
  required bool includeBefore,
}) sync* {
  if (rule.frequency.isSmall) {
    yield* _smallFrequencyOccurrences(
      rule: rule,
      dtStart: dtStart,
      before: before,
      includeBefore: includeBefore,
    );
    return;
  }

  final periodDtStart = rule.frequency._periodStartFor(
    dtStart,
    rule.byWeekDays,
  );
  final scanStart =
      rule.bySetPositions.isNotEmpty ? periodDtStart : dtStart._dateOnly();
  final bySetPosExists = rule.bySetPositions.isNotEmpty;
  final intervalCandidates = <DateTime>[];
  int? currentBySetPosPeriodKey;

  for (var day = scanStart; day <= before; day = day.shift(days: 1)) {
    if (bySetPosExists) {
      final nextBySetPosKey = rule.frequency._periodKey(dtStart, day);

      if (currentBySetPosPeriodKey != nextBySetPosKey) {
        yield* intervalCandidates._filterByBySetPos(
          bySetPositions: rule.bySetPositions,
          dtStart: dtStart,
          before: before,
          includeBefore: includeBefore,
        );
        intervalCandidates.clear();

        currentBySetPosPeriodKey = nextBySetPosKey;
      }
    }

    if (!day._isInFrequencyPeriod(rrule: rule, dtStart: periodDtStart)) {
      continue;
    }
    if (!day._matchesDateFilters(rule)) continue;

    final hours = (rule.byHours.isNotEmpty) ? rule.byHours : [dtStart.hour];
    final minutes =
        (rule.byMinutes.isNotEmpty) ? rule.byMinutes : [dtStart.minute];
    final seconds =
        (rule.bySeconds.isNotEmpty) ? rule.bySeconds : [dtStart.second];

    for (final h in hours) {
      for (final m in minutes) {
        for (final s in seconds) {
          final candidate = DateTime.utc(
            day.year,
            day.month,
            day.day,
            h,
            m,
            s,
            dtStart.millisecond,
            dtStart.microsecond,
          );

          if (includeBefore ? candidate > before : candidate >= before) {
            continue;
          }
          if (!candidate._matchesYearAndWeekFilters(rule)) continue;
          if (bySetPosExists) {
            intervalCandidates.add(candidate);
            continue;
          }
          if (candidate < dtStart) continue;
          yield candidate;
        }
      }
    }
  }
  yield* intervalCandidates._filterByBySetPos(
    bySetPositions: rule.bySetPositions,
    dtStart: dtStart,
    before: before,
    includeBefore: includeBefore,
  );
}

extension on List<DateTime> {
  Iterable<DateTime> _filterByBySetPos({
    required List<int> bySetPositions,
    required DateTime dtStart,
    required DateTime before,
    required bool includeBefore,
  }) sync* {
    if (isEmpty) return;
    for (final candidate in _applyBySetPos(this, bySetPositions)) {
      if (candidate < dtStart) continue;
      if (includeBefore ? candidate > before : candidate >= before) return;
      yield candidate;
    }
  }
}

Iterable<DateTime> _smallFrequencyOccurrences({
  required RecurrenceRule rule,
  required DateTime dtStart,
  required DateTime before,
  required bool includeBefore,
}) sync* {
  // TODO(bornold): Respect BYSETPOS for these frequencies
  final interval = rule.interval ?? 1;
  for (var current = dtStart;
      includeBefore ? before > current : before >= current;
      current = rule.frequency._stepFine(interval, current)) {
    if (current._matchesFullFilters(rule)) {
      yield current;
    }
  }
}

extension on Frequency {
  bool get isSmall =>
      this == Frequency.secondly ||
      this == Frequency.minutely ||
      this == Frequency.hourly;

  DateTime _stepFine(int interval, DateTime dt) {
    switch (this) {
      case Frequency.secondly:
        return dt.add(Duration(seconds: interval));
      case Frequency.minutely:
        return dt.add(Duration(minutes: interval));
      case Frequency.hourly:
        return dt.add(Duration(hours: interval));
      case Frequency.daily:
      case Frequency.weekly:
      case Frequency.monthly:
      case Frequency.yearly:
    }
    throw StateError('Only use this for frequencies greater than daily.');
  }

  DateTime _periodStartFor(DateTime dtStart, List<ByWeekDayEntry> weekDays) {
    final date = dtStart._dateOnly();
    switch (this) {
      case Frequency.yearly:
        return DateTime.utc(date.year);
      case Frequency.monthly:
        return DateTime.utc(date.year, date.month);
      case Frequency.weekly:
        final largestWeekDay = weekDays.fold(
          0,
          (d, n) => max(n.day + (n.occurrence ?? 0) % DateTime.daysPerWeek, d),
        );
        final delta = largestWeekDay < date.weekday
            ? date.weekday - DateTime.daysPerWeek
            : date.weekday - DateTime.monday;
        return date.subtract(Duration(days: delta));
      case Frequency.daily:
      case Frequency.secondly:
      case Frequency.minutely:
      case Frequency.hourly:
    }
    return date;
  }

  int _periodKey(DateTime dtStartUtc, DateTime day) {
    switch (this) {
      case Frequency.yearly:
        return day.year;
      case Frequency.monthly:
        return day.year * DateTime.monthsPerYear + day.month;
      case Frequency.weekly:
        final startDay = dtStartUtc._dateOnly();
        final diffDays = day.difference(startDay).inDays;
        return diffDays ~/ DateTime.daysPerWeek;
      case Frequency.daily:
      case Frequency.hourly:
      case Frequency.minutely:
      case Frequency.secondly:
    }
    return day._dateOnly().millisecondsSinceEpoch;
  }
}

List<DateTime> _applyBySetPos(
  List<DateTime> candidates,
  List<int> bySetPositions,
) {
  if (candidates.isEmpty) return const [];
  if (bySetPositions.isEmpty) {
    return List<DateTime>.of(candidates);
  }
  final len = candidates.length;
  return bySetPositions
      .map((position) => position > 0 ? position - 1 : len + position)
      .where((index) => index >= 0 && index < len)
      .map((index) => candidates[index])
      .toList();
}

extension on DateTime {
  DateTime _dateOnly() => DateTime.utc(year, month, day);

  bool _isInFrequencyPeriod({
    required RecurrenceRule rrule,
    required DateTime dtStart,
  }) {
    final interval_ = rrule.interval ?? 1;
    final startDay = dtStart._dateOnly();
    if (this < startDay) return false;

    switch (rrule.frequency) {
      case Frequency.daily:
        final diffDays = difference(startDay).inDays;
        return diffDays % interval_ == 0;

      case Frequency.weekly:
        final diffDays = difference(startDay).inDays;
        final weeks = diffDays ~/ DateTime.daysPerWeek;
        return weeks >= 0 && weeks % interval_ == 0;

      case Frequency.monthly:
        final months = (year - startDay.year) * DateTime.monthsPerYear +
            (month - startDay.month);
        return months >= 0 && months % interval_ == 0;

      case Frequency.yearly:
        final years = year - startDay.year;
        return years >= 0 && years % interval_ == 0;

      case Frequency.hourly:
      case Frequency.minutely:
      case Frequency.secondly:
    }
    return false;
  }

  bool _matchesFullFilters(RecurrenceRule rrule) {
    if (rrule.bySeconds.isNotEmpty) {
      if (!rrule.bySeconds.contains(second)) return false;
    }
    if (rrule.byMinutes.isNotEmpty) {
      if (!rrule.byMinutes.contains(minute)) return false;
    }
    if (rrule.byHours.isNotEmpty) {
      if (!rrule.byHours.contains(hour)) return false;
    }

    if (!_dateOnly()._matchesDateFilters(rrule)) return false;
    if (!_matchesYearAndWeekFilters(rrule)) return false;
    return true;
  }

  bool _matchesDateFilters(RecurrenceRule rrule) {
    if (rrule.byMonths.isNotEmpty) {
      if (!rrule.byMonths.contains(month)) return false;
    }

    if (rrule.byWeekDays.isNotEmpty) {
      final hasByMonth =
          rrule.byMonths.isNotEmpty || rrule.frequency == Frequency.monthly;
      if (rrule.byWeekDays.none(
        (weekday) => _matchesByDayMonth(weekday, hasByMonth: hasByMonth),
      )) {
        return false;
      }
    }

    if (rrule.byMonthDays.isNotEmpty) {
      final day_ = day;
      final daysInMonth_ = daysInMonth;
      return rrule.byMonthDays
          .map(
            (monthDay) => monthDay > 0 ? monthDay : daysInMonth_ + 1 + monthDay,
          )
          .any((target) => target == day_);
    }
    return true;
  }

  bool _matchesByDayMonth(
    ByWeekDayEntry entry, {
    required bool hasByMonth,
  }) {
    final occurrence = entry.occurrence;
    if (entry.day != weekday) return false;
    if (occurrence == null) return true;
    if (occurrence == 0) return false;

    final target = occurrence > 0
        ? _nthWeekdayInMonth(
            year,
            hasByMonth ? month : 1,
            entry.day,
            occurrence,
          )
        : _lastNthWeekdayInMonth(
            year,
            hasByMonth ? month : DateTime.monthsPerYear,
            entry.day,
            occurrence,
          );
    return target == this;
  }

  bool _matchesYearAndWeekFilters(RecurrenceRule rrule) {
    if (rrule.byYearDays.isNotEmpty &&
        rrule.byYearDays
            .map((yearDay) => yearDay > 0 ? yearDay : daysInYear + 1 + yearDay)
            .none((target) => dayOfYear == target)) {
      return false;
    }

    if (rrule.byWeeks.isNotEmpty) {
      final week = _dateOnly().weekInfo.weekOfYear;
      final weeksInYear = WeekInfo.weeksInYear(year);
      return rrule.byWeeks
          .map((byWeek) => byWeek > 0 ? byWeek : weeksInYear + 1 + byWeek)
          .any((target) => week == target);
    }
    return true;
  }
}

DateTime _nthWeekdayInMonth(int year, int month, int weekday, int occurrence) {
  final firstDay = DateTime.utc(year, month);
  var diff = weekday - firstDay.weekday;
  if (diff < 0) diff += DateTime.daysPerWeek;
  final day = diff + 1 + (occurrence - 1) * DateTime.daysPerWeek;
  return DateTime.utc(year, month, day);
}

DateTime _lastNthWeekdayInMonth(
  int year,
  int month,
  int weekday,
  int occurrence,
) {
  final lastDay = DateTime.utc(year, month + 1, 0);
  var diff = lastDay.weekday - weekday;
  if (diff < 0) diff += DateTime.daysPerWeek;
  final offset = diff + (-occurrence - 1) * DateTime.daysPerWeek;
  final day = lastDay.day - offset;
  return DateTime.utc(year, month, day);
}
