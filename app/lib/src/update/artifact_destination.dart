/// The user-consented destination picker for macOS update artifacts.
///
/// A sandboxed macOS app that silently writes a downloaded installer into its
/// container marks it as created without user consent. Gatekeeper then refuses
/// to launch an app installed from that image. Using the native Save As panel
/// gives the user control of the destination and records the expected download
/// provenance.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';

import 'update_config.dart';
import 'update_manifest.dart';

/// Selects a destination for the named artifact, returning `null` on cancel.
typedef ArtifactDestinationPicker =
    Future<File?> Function(UpdateArtifact artifact);

/// Injectable wrapper around the native Save As panel for unit tests.
typedef SaveLocationPicker =
    Future<FileSaveLocation?> Function({
      required String suggestedName,
      required List<XTypeGroup> acceptedTypeGroups,
    });

const _macosUpdateTypeGroup = XTypeGroup(
  label: "Caller's Compendium update",
  extensions: ['dmg', 'zip'],
  uniformTypeIdentifiers: ['com.apple.disk-image', 'public.zip-archive'],
);

/// Opens the macOS native Save As panel and returns the selected destination.
///
/// The caller writes the artifact directly to this path using its existing
/// exclusive-create guard. Returning `null` means the user cancelled and no
/// download should begin.
Future<File?> pickMacosArtifactDestination(
  UpdateArtifact artifact, {
  SaveLocationPicker saveLocationPicker = _showMacosSaveLocation,
}) async {
  final location = await saveLocationPicker(
    suggestedName: downloadFileName(artifact.url),
    acceptedTypeGroups: const [_macosUpdateTypeGroup],
  );
  return location == null ? null : File(location.path);
}

Future<FileSaveLocation?> _showMacosSaveLocation({
  required String suggestedName,
  required List<XTypeGroup> acceptedTypeGroups,
}) {
  return getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: acceptedTypeGroups,
  );
}
