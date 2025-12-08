import 'package:time/time.dart';

import '../recurrence_rule.dart';
import '../utils.dart';

Iterable<DateTime> buildSetPositionsList(
  RecurrenceRule rrule,
  Iterable<DateTime> includedDays,
  Iterable<Duration> timeSet,
) sync* {
  assert(timeSet.every((it) => it.isValidRruleTimeOfDay));

  final dateIndices = includedDays.toList();
  if (dateIndices.isEmpty) return;

  final timeList = timeSet.toList(growable: false);
  for (final setPosition in rrule.bySetPositions) {
    final correctedSetPosition =
        setPosition < 0 ? setPosition : setPosition - 1;
    final datePosition = correctedSetPosition ~/ timeList.length;
    final timePosition = correctedSetPosition % timeList.length;

    if (datePosition >= dateIndices.length ||
        -datePosition > dateIndices.length) {
      continue;
    }

    final dateIndex = dateIndices[datePosition % dateIndices.length];
    yield dateIndex + timeList[timePosition];
  }
}
