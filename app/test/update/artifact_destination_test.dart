import 'package:compendium_app/src/update/artifact_destination.dart';
import 'package:compendium_app/src/update/update_manifest.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const artifact = UpdateArtifact(
    platform: UpdatePlatform.macos,
    arch: UpdateArch.universal,
    url:
        'https://github.com/ibanner56/CallersCompendium/releases/download/v0.2.0/CallersCompendium-0.2.0-macos-universal.dmg',
    sha256: 'abcd',
    size: 4,
  );

  test(
    'macOS picker requests a user-selected disk-image destination',
    () async {
      String? receivedSuggestedName;
      List<XTypeGroup>? receivedTypeGroups;

      final destination = await pickMacosArtifactDestination(
        artifact,
        saveLocationPicker:
            ({
              required String suggestedName,
              required List<XTypeGroup> acceptedTypeGroups,
            }) async {
              receivedSuggestedName = suggestedName;
              receivedTypeGroups = acceptedTypeGroups;
              return const FileSaveLocation('/Users/test/Downloads/update.dmg');
            },
      );

      expect(destination?.path, '/Users/test/Downloads/update.dmg');
      expect(
        receivedSuggestedName,
        'CallersCompendium-0.2.0-macos-universal.dmg',
      );
      expect(receivedTypeGroups, hasLength(1));
      expect(receivedTypeGroups!.single.extensions, ['dmg', 'zip']);
      expect(receivedTypeGroups!.single.uniformTypeIdentifiers, [
        'com.apple.disk-image',
        'public.zip-archive',
      ]);
    },
  );

  test('macOS picker returns null when the user cancels', () async {
    final destination = await pickMacosArtifactDestination(
      artifact,
      saveLocationPicker:
          ({required suggestedName, required acceptedTypeGroups}) async => null,
    );

    expect(destination, isNull);
  });
}
