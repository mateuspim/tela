import 'package:tela/domain/models/stored_image_condition.dart';

/// Reads the native `inspectImages` reply into one condition per location.
///
/// Padded to [expected] with [StoredImageCondition.unreadable], and so is any
/// word it does not know: a short or garbled reply must never make a healthy
/// file look broken, because broken is what gets overwritten or deleted.
///
/// ```dart
/// conditionsFromReply({'conditions': ['empty']}, 2);
/// // [StoredImageCondition.empty, StoredImageCondition.unreadable]
/// ```
List<StoredImageCondition> conditionsFromReply(Object? raw, int expected) {
  final Object? words = raw is Map<Object?, Object?> ? raw['conditions'] : null;
  final List<Object?> list = words is List<Object?> ? words : const <Object?>[];
  return <StoredImageCondition>[
    for (int i = 0; i < expected; i++)
      i < list.length
          ? _conditionNamed(list[i])
          : StoredImageCondition.unreadable,
  ];
}

StoredImageCondition _conditionNamed(Object? word) {
  return StoredImageCondition.values
          .where((StoredImageCondition c) => c.name == word)
          .firstOrNull ??
      StoredImageCondition.unreadable;
}
