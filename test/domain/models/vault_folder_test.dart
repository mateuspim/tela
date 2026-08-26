import 'package:flutter_test/flutter_test.dart';
import 'package:tela/domain/models/vault_folder.dart';

void main() {
  group('VaultFolder', () {
    test('the standard vault is a hidden tela folder', () {
      expect(VaultFolder.standard.label, 'tela');
      expect(VaultFolder.standard.directoryName, '.tela');
    });

    test('a label becomes a hidden directory', () {
      expect(VaultFolder('stash').directoryName, '.stash');
    });

    // The dot is the app's, composed here. A label carrying one would either
    // double it or have to be stripped somewhere that could forget.
    test('a label may not carry its own dot', () {
      expect(VaultFolder.isLegal('.stash'), isFalse);
      expect(() => VaultFolder('.stash'), throwsArgumentError);
    });

    test('the message names the offending value and the shape', () {
      expect(
        () => VaultFolder('../secrets'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message.toString(),
            'message',
            allOf(contains('../secrets'), contains('leading dot')),
          ),
        ),
      );
    });

    /// The whole reason the label goes through the tag allowlist: it becomes a
    /// directory name on the other side of a method channel, so nothing that
    /// could traverse may pass the constructor.
    test('traversal and separators are never legal labels', () {
      for (final String label in <String>['..', '.', 'a/b', '', ' ']) {
        expect(VaultFolder.isLegal(label), isFalse, reason: label);
      }
    });

    /// Sanitizing is the repairing door and it must still not produce one:
    /// `..` reduces to nothing at all, and a separator becomes a space rather
    /// than a path — the substitution rule `TagFolder.sanitize` argues for.
    test('sanitizing a traversal yields nothing at all', () {
      expect(VaultFolder.sanitize('..'), isNull);
      expect(VaultFolder.sanitize('.'), isNull);
      expect(VaultFolder.sanitize('   '), isNull);
    });

    /// Someone typing the folder they can see is naming it, not erring — and
    /// the dot they typed is the one this class adds back.
    test('sanitize drops a leading dot rather than refusing it', () {
      expect(VaultFolder.sanitize('.stash'), VaultFolder('stash'));
    });

    test('sanitize repairs what it can and drops what it cannot', () {
      expect(VaultFolder.sanitize('  my stash  '), VaultFolder('my stash'));
      // A separator becomes a space, never a path segment.
      expect(VaultFolder.sanitize('a/b'), VaultFolder('a b'));
      expect(VaultFolder.sanitize('>_<'), isNull);
    });

    test('two vaults with the same label are the same vault', () {
      expect(VaultFolder('stash'), VaultFolder('stash'));
      expect(VaultFolder('stash').hashCode, VaultFolder('stash').hashCode);
      expect(VaultFolder('stash') == VaultFolder('other'), isFalse);
    });

    /// Safe to print because it names a folder and nothing in it — the same
    /// rule `TagFolder.toString` follows.
    test('printing it names the directory and no file', () {
      expect(VaultFolder('stash').toString(), '.stash');
    });

    /// The visible folder is `tela`; the vault is its hidden sibling. If those
    /// ever named one directory, the hiding would do nothing.
    test('the vault is never the visible folder', () {
      expect(VaultFolder.standard.directoryName, isNot('tela'));
    });
  });
}
