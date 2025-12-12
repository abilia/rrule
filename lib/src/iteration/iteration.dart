import '../by_week_day_entry.dart';
import '../codecs/string/ical.dart';
import '../frequency.dart';
import '../recurrence_rule.dart';
import '../utils.dart';
import 'expand_occurrences.dart';

/// The actual calculation of recurring instances of [rrule].
///
/// Inspired by https://github.com/jakubroztocil/rrule/blob/df660bf5973cf4ec993738c2cca0f4cec1f9c6e6/src/iter/index.ts.
Iterable<DateTime> getRecurrenceRuleInstances(
  RecurrenceRule rrule, {
  required DateTime start,
  DateTime? after,
  bool includeAfter = false,
  DateTime? before,
  bool includeBefore = false,
}) sync* {
  assert(start.isValidRruleDateTime);
  assert(after.isValidRruleDateTime);
  assert(before.isValidRruleDateTime);
  if (after != null) assert(after >= start);
  if (before != null) assert(before >= start);

  rrule = _prepare(rrule, start);

  final count = rrule.count;
  if (count == 0) return;

  final until = rrule.until;
  final newBefore = before ?? until ?? DateTime.utc(iCalMaxYear);
  final useUntil = until != null && until < newBefore;
  final limitEnd = useUntil ? until : newBefore;

  var occurrences = expandOccurrences(
    rule: rrule,
    dtStart: start,
    before: limitEnd,
    includeBefore: useUntil || includeBefore,
  );
  if (count != null) occurrences = occurrences.take(count);
  if (after != null) {
    if (includeAfter) {
      occurrences = occurrences.where((d) => d >= after);
    } else {
      occurrences = occurrences.where((d) => d > after);
    }
  }
  yield* occurrences;
}

RecurrenceRule _prepare(RecurrenceRule rrule, DateTime start) {
  assert(start.isValidRruleDateTime);

  final byDatesEmpty = rrule.byWeekDays.isEmpty &&
      rrule.byMonthDays.isEmpty &&
      rrule.byYearDays.isEmpty &&
      rrule.byWeeks.isEmpty;

  return RecurrenceRule(
    frequency: rrule.frequency,
    until: rrule.until,
    count: rrule.count,
    interval: rrule.interval,
    bySeconds: rrule.bySeconds.isEmpty && rrule.frequency < Frequency.secondly
        ? [start.second]
        : rrule.bySeconds,
    byMinutes: rrule.byMinutes.isEmpty && rrule.frequency < Frequency.minutely
        ? [start.minute]
        : rrule.byMinutes,
    byHours: rrule.byHours.isEmpty && rrule.frequency < Frequency.hourly
        ? [start.hour]
        : rrule.byHours,
    byWeekDays: byDatesEmpty && rrule.frequency == Frequency.weekly
        ? [ByWeekDayEntry(start.weekday)]
        : rrule.byWeekDays,
    byMonthDays: byDatesEmpty &&
            (rrule.frequency == Frequency.monthly ||
                rrule.frequency == Frequency.yearly)
        ? [start.day]
        : rrule.byMonthDays,
    byYearDays: rrule.byYearDays,
    byWeeks: rrule.byWeeks,
    byMonths: byDatesEmpty &&
            rrule.frequency == Frequency.yearly &&
            rrule.byMonths.isEmpty
        ? [start.month]
        : rrule.byMonths,
    bySetPositions: rrule.bySetPositions,
    weekStart: rrule.weekStart,
  );
}
