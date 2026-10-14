import 'package:flutter_test/flutter_test.dart';
import 'package:tela/data/storage/stored_image_condition_reply.dart';
import 'package:tela/domain/models/stored_image_condition.dart';

/// A garbled reply must never make a healthy file look broken — broken is what
/// gets overwritten or deleted.
void main() {
  test('reads each word into its condition, in order', () {
    expect(
      conditionsFromReply(<String, Object>{
        'conditions': <String>['intact', 'empty', 'truncated', 'unreadable'],
      }, 4),
      StoredImageCondition.values,
    );
  });

  test('pads a short reply with unreadable', () {
    expect(
      conditionsFromReply(<String, Object>{
        'conditions': <String>['empty'],
      }, 2),
      <StoredImageCondition>[
        StoredImageCondition.empty,
        StoredImageCondition.unreadable,
      ],
    );
  });

  test('an unknown word or a missing reply is unreadable, never broken', () {
    expect(
      conditionsFromReply(<String, Object>{
        'conditions': <Object>['shredded', 3],
      }, 2),
      everyElement(StoredImageCondition.unreadable),
    );
    expect(
      conditionsFromReply(null, 1),
      <StoredImageCondition>[StoredImageCondition.unreadable],
    );
  });
}
