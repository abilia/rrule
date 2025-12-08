import 'package:collection/collection.dart';

import '../../rrule.dart';
import '../utils.dart';

Iterable<DateTime> expandOccurrences({
  required RecurrenceRule rule,
  required DateTime dtStart,
  required DateTime from,
  required DateTime to,
}) sync* {
  if (to.isBefore(from)) return;

  final until = rule.until;
  final interval = rule.interval ?? 1;
  var limitEnd = to;
  if (until != null && until.isBefore(limitEnd)) {
    limitEnd = until;
  }

  var produced = 0;

  if (rule.frequency == Frequency.secondly ||
      rule.frequency == Frequency.minutely ||
      rule.frequency == Frequency.hourly) {
    var current = dtStart;

    while (!current.isAfter(limitEnd)) {
      if (rule.count != null && produced >= rule.count!) break;

      if (!current.isBefore(from) && _matchesFullFilters(current, rule)) {
        yield current;
        produced++;
      }

      current = _stepFine(rule.frequency, interval, current);
    }

    return;
  }

  final dateStart = _dateOnly(dtStart);
  final dateEnd = _dateOnly(limitEnd);

  final scanStart = rule.bySetPositions.isNotEmpty
      ? _periodStartFor(rule.frequency, dtStart)
      : dateStart;

  var day = scanStart;
  Object? currentPeriodKey;
  final periodCandidates = <DateTime>[];

  Iterable<DateTime> flushCurrentPeriod() sync* {
    if (periodCandidates.isEmpty) return;
    final selected = _applyBySetPos(periodCandidates, rule.bySetPositions);

    for (final candidate in selected) {
      if (rule.count != null && produced >= rule.count!) return;
      if (candidate.isBefore(dtStart)) continue;
      if (candidate.isAfter(limitEnd)) return;

      if (!candidate.isBefore(from)) {
        yield candidate;
      }
      produced++;
    }

    periodCandidates.clear();
  }

  final frequencyCheckStart =
      rule.frequency == Frequency.monthly ? scanStart : dtStart;

  while (!day.isAfter(dateEnd)) {
    if (rule.count != null && produced >= rule.count!) break;

    if (_isInFrequencyPeriod(
      rule.frequency,
      interval,
      frequencyCheckStart,
      day,
    )) {
      final key = rule.bySetPositions.isEmpty
          ? null
          : _periodKey(rule.frequency, dtStart, day);

      if (currentPeriodKey == null) {
        currentPeriodKey = key;
      } else if (key != currentPeriodKey) {
        yield* flushCurrentPeriod();
        if (rule.count != null && produced >= rule.count!) break;
        currentPeriodKey = key;
      }

      if (_matchesDateFilters(day, rule)) {
        final hours = (rule.byHours.isNotEmpty) ? rule.byHours : [dtStart.hour];

        final minutes =
            (rule.byMinutes.isNotEmpty) ? rule.byMinutes : [dtStart.minute];

        final seconds =
            (rule.bySeconds.isNotEmpty) ? rule.bySeconds : [dtStart.second];

        for (final h in hours) {
          for (final m in minutes) {
            for (final s in seconds) {
              if (rule.count != null && produced >= rule.count!) break;

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

              if (candidate.isAfter(limitEnd)) continue;

              if (!_matchesYearAndWeekFilters(candidate, rule)) continue;

              if (currentPeriodKey != null) {
                periodCandidates.add(candidate);
              } else {
                if (candidate.isBefore(dtStart)) continue;
                produced++;
                if (!candidate.isBefore(from)) {
                  yield candidate;
                }
              }
            }
          }
        }
      }
    }

    day = day.add(const Duration(days: 1));
  }

  if (rule.count == null || produced < rule.count!) {
    yield* flushCurrentPeriod();
  }
}

DateTime _periodStartFor(Frequency freq, DateTime dtStart) {
  final d = _dateOnly(dtStart);
  switch (freq) {
    case Frequency.daily:
      return d;
    case Frequency.weekly:
      final delta = d.weekday - DateTime.monday;
      return d.subtract(Duration(days: delta));
    case Frequency.monthly:
      return DateTime.utc(d.year, d.month);
    case Frequency.yearly:
      return DateTime.utc(d.year);
    case Frequency.secondly:
    case Frequency.minutely:
    case Frequency.hourly:
      return d;
  }
  throw StateError('Invalid frequency');
}

Object _periodKey(Frequency freq, DateTime dtStartUtc, DateTime day) {
  switch (freq) {
    case Frequency.daily:
      return _dateOnly(day);
    case Frequency.weekly:
      final startDay = _dateOnly(dtStartUtc);
      final diffDays = day.difference(startDay).inDays;
      final weekIndex = diffDays ~/ DateTime.daysPerWeek;
      return weekIndex;
    case Frequency.monthly:
      return day.year * DateTime.monthsPerYear + day.month;
    case Frequency.yearly:
      return day.year;
    case Frequency.hourly:
    case Frequency.minutely:
    case Frequency.secondly:
      return _dateOnly(day);
  }
  return _dateOnly(day);
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
  final selected = <DateTime>[];

  final indices = <int>{};
  for (final position in bySetPositions) {
    final index = position > 0 ? position - 1 : len + position;
    if (index >= 0 && index < len) {
      indices.add(index);
    }
  }

  final sortedIndex = indices.toList()..sort();
  for (final i in sortedIndex) {
    selected.add(candidates[i]);
  }
  return selected;
}

bool _isInFrequencyPeriod(
  Frequency frequency,
  int interval,
  DateTime dtStart,
  DateTime day,
) {
  final startDay = _dateOnly(dtStart);
  if (day.isBefore(startDay)) return false;

  switch (frequency) {
    case Frequency.daily:
      final diffDays = day.difference(startDay).inDays;
      return diffDays % interval == 0;

    case Frequency.weekly:
      final diffDays = day.difference(startDay).inDays;
      final weeks = diffDays ~/ 7;
      return weeks >= 0 && weeks % interval == 0;

    case Frequency.monthly:
      final months = (day.year - startDay.year) * DateTime.monthsPerYear +
          (day.month - startDay.month);
      return months >= 0 && months % interval == 0;

    case Frequency.yearly:
      final years = day.year - startDay.year;
      return years >= 0 && years % interval == 0;

    case Frequency.hourly:
    case Frequency.minutely:
    case Frequency.secondly:
      return false;
  }
  return false;
}

bool _matchesDateFilters(DateTime day, RecurrenceRule rule) {
  final year = day.year;
  final month = day.month;
  final dayInMonth = day.day;

  if (rule.byMonths.isNotEmpty) {
    if (!rule.byMonths.contains(month)) return false;
  }

  if (rule.byWeekDays.isNotEmpty) {
    if (rule.byWeekDays.none(
      (weekday) => _matchesByDayMonth(
        day,
        weekday,
        hasByMonth:
            rule.byMonths.isNotEmpty || rule.frequency == Frequency.monthly,
      ),
    )) {
      return false;
    }
  }

  if (rule.byMonthDays.isNotEmpty) {
    final daysInMonth = _daysInMonth(year, month);
    var ok = false;
    for (final monthDay in rule.byMonthDays) {
      final targetDay = monthDay > 0 ? monthDay : daysInMonth + 1 + monthDay;
      if (dayInMonth == targetDay) {
        ok = true;
        break;
      }
    }
    if (!ok) return false;
  }

  return true;
}

bool _matchesYearAndWeekFilters(DateTime dt, RecurrenceRule rule) {
  final year = dt.year;

  if (rule.byYearDays.isNotEmpty) {
    final daysInYear = dt.daysInYear;
    final dayOfYear = dt.dayOfYear;

    var ok = false;
    for (final yearDay in rule.byYearDays) {
      final target = yearDay > 0 ? yearDay : daysInYear + 1 + yearDay;
      if (dayOfYear == target) {
        ok = true;
        break;
      }
    }
    if (!ok) return false;
  }

  if (rule.byWeeks.isNotEmpty) {
    final week = _isoWeekNumber(dt);
    final weeksInYear = _isoWeeksInYear(year);

    var ok = false;
    for (final byWeek in rule.byWeeks) {
      final target = byWeek > 0 ? byWeek : weeksInYear + 1 + byWeek;
      if (week == target) {
        ok = true;
        break;
      }
    }
    if (!ok) return false;
  }

  return true;
}

bool _matchesFullFilters(DateTime dt, RecurrenceRule rule) {
  if (rule.bySeconds.isNotEmpty) {
    if (!rule.bySeconds.contains(dt.second)) return false;
  }
  if (rule.byMinutes.isNotEmpty) {
    if (!rule.byMinutes.contains(dt.minute)) return false;
  }
  if (rule.byHours.isNotEmpty) {
    if (!rule.byHours.contains(dt.hour)) return false;
  }

  if (!_matchesDateFilters(_dateOnly(dt), rule)) return false;
  if (!_matchesYearAndWeekFilters(dt, rule)) return false;

  return true;
}

DateTime _stepFine(Frequency frequency, int interval, DateTime dt) {
  switch (frequency) {
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
      throw StateError('Only use this for frequencies greater than daily.');
  }
  throw StateError('Only use this for frequencies greater than daily.');
}

DateTime _dateOnly(DateTime dt) => DateTime.utc(dt.year, dt.month, dt.day);

bool _isLeapYear(int year) {
  if (year % 4 != 0) return false;
  if (year % 100 != 0) return true;
  return year % 400 == 0;
}

int _daysInMonth(int year, int month) {
  final nextMonth = (month == DateTime.monthsPerYear)
      ? DateTime.utc(year + 1)
      : DateTime.utc(year, month + 1);
  final thisMonth = DateTime.utc(year, month);
  return nextMonth.difference(thisMonth).inDays;
}

int _dayOfYear(DateTime dt) {
  final startOfYear = DateTime.utc(dt.year);
  return dt.difference(startOfYear).inDays + 1;
}

int _isoWeekNumber(DateTime dt) {
  final dayOfYear = _dayOfYear(dt);
  final weekday = dt.weekday;
  final woy = (dayOfYear - weekday + 10) ~/ DateTime.daysPerWeek;

  if (woy < 1) {
    return _isoWeeksInYear(dt.year - 1);
  } else {
    final weeksInYear = _isoWeeksInYear(dt.year);
    if (woy > weeksInYear) {
      return 1;
    } else {
      return woy;
    }
  }
}

int _isoWeeksInYear(int year) {
  final dec31 = DateTime.utc(year, DateTime.monthsPerYear, 31);
  final weekday = dec31.weekday;

  if (weekday == DateTime.thursday) return 53;
  if (weekday == DateTime.friday && _isLeapYear(year)) return 53;
  return 52;
}

bool _matchesByDayMonth(
  DateTime dt,
  ByWeekDayEntry entry, {
  bool hasByMonth = false,
}) {
  final occurrence = entry.occurrence;
  if (entry.day != dt.weekday) return false;
  if (occurrence == null) return true;
  if (occurrence == 0) return false;

  final target = occurrence > 0
      ? nthWeekdayInMonth(
          dt.year,
          hasByMonth ? dt.month : 1,
          entry.day,
          occurrence,
        )
      : lastNthWeekdayInMonth(
          dt.year,
          hasByMonth ? dt.month : DateTime.monthsPerYear,
          entry.day,
          occurrence,
        );
  return target == dt;
}

DateTime nthWeekdayInMonth(int year, int month, int weekday, int occurrence) {
  final first = DateTime.utc(year, month);

  var diff = weekday - first.weekday;
  if (diff < 0) diff += DateTime.daysPerWeek;

  final day = diff + 1 + (occurrence - 1) * DateTime.daysPerWeek;

  return DateTime.utc(year, month, day);
}

DateTime lastNthWeekdayInMonth(
  int year,
  int month,
  int weekday,
  int occurrence,
) {
  final lastDay =
      DateTime.utc(year, month + 1).subtract(const Duration(days: 1));

  var diff = lastDay.weekday - weekday;
  if (diff < 0) diff += 7;

  final offset = diff + (-occurrence - 1) * DateTime.daysPerWeek;
  final day = lastDay.day - offset;

  return DateTime.utc(year, month, day);
}
