package org.callerscompendium.compendiumApp

import java.io.File
import java.io.FileOutputStream

/**
 * The marker Dart's `restored_copy_check.dart` uses to recognise a library
 * restored from a device backup (sync-spec §3.3). MainActivity keeps it in
 * `noBackupFilesDir`, which Auto Backup and device-to-device transfer never
 * copy and the system never clears on its own (unlike the cache). Free of
 * Android types so src/test can unit-test it.
 */
class NoBackupMarker(directory: File) {
    private val file = File(directory, FILE_NAME)

    fun exists(): Boolean = file.exists()

    /** Creates the marker if it is missing. Synced to disk before it returns,
     * because Dart records the marker as written once this succeeds, and a
     * marker lost to a power cut after that would read as a restore. */
    fun write() {
        if (file.exists()) return
        FileOutputStream(file).use {
            it.write(1)
            it.fd.sync()
        }
    }

    companion object {
        const val FILE_NAME = "device_backup_marker"
    }
}
