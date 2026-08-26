import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/vault_thumbnail.dart';

void main() {
  test('aspectRatio divides the source pixel dimensions', () {
    const VaultThumbnail thumbnail = VaultThumbnail(
      path: '/cache/thumb-1',
      width: 1080,
      height: 2400,
    );

    expect(thumbnail.aspectRatio, closeTo(1080 / 2400, 1e-9));
  });

  test('equality is by path and both dimensions', () {
    const VaultThumbnail a = VaultThumbnail(
      path: '/cache/thumb-1',
      width: 1080,
      height: 2400,
    );
    const VaultThumbnail sameValues = VaultThumbnail(
      path: '/cache/thumb-1',
      width: 1080,
      height: 2400,
    );
    const VaultThumbnail differentPath = VaultThumbnail(
      path: '/cache/thumb-2',
      width: 1080,
      height: 2400,
    );

    expect(a, sameValues);
    expect(a.hashCode, sameValues.hashCode);
    expect(a, isNot(differentPath));
  });
}
