# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Path Provider specific
-keep class io.flutter.plugins.pathprovider.** { *; }

# Pigeon generated classes e interfaces
-keep class dev.flutter.pigeon.** { *; }
-keep interface dev.flutter.pigeon.** { *; }

# Registro automático de plugins
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# sqflite rules
-keep class com.tekartik.sqflite.** { *; }
-keep class io.sqlcipher.IBitmapCursor { *; }
-keep class io.sqlcipher.database.SQLiteDatabase { *; }
-keep class io.sqlcipher.database.SQLiteCursor { *; }
-keep class io.sqlcipher.database.SQLiteOpenHelper { *; }
-keep class io.sqlcipher.database.SQLiteStatement { *; }
-keep class io.sqlcipher.database.SQLiteQuery { *; }
-keep class io.sqlcipher.database.SQLiteDirectCursorDriver { *; }
-keep class io.sqlcipher.database.SQLiteQueryBuilder { *; }
-keep class io.sqlcipher.database.SQLiteContentHelper { *; }
-keep class io.sqlcipher.database.SQLiteCursorDriver { *; }
-keep class io.sqlcipher.database.SQLiteProgram { *; }
-keep class io.sqlcipher.database.SQLiteQuery { *; }
-keep class io.sqlcipher.database.SQLiteStatement { *; }
-keep class io.sqlcipher.database.SQLiteDatabaseHook { *; }
-keep class io.sqlcipher.database.SQLiteDatabase$CursorFactory { *; }
-keep class io.sqlcipher.database.SQLiteDatabase$CustomFunction { *; }

# JNI rules
-keepclassmembers class * {
    native <methods>;
}

# Google Play Core (to suppress R8 errors if not using Play Core library)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task

# just_audio y audio_session
-keep class com.ryanheise.just_audio.** { *; }
-keep class com.ryanheise.audio_session.** { *; }
-keep interface com.ryanheise.just_audio.** { *; }
-keep interface com.ryanheise.audio_session.** { *; }
-dontwarn com.ryanheise.just_audio.**
-dontwarn com.ryanheise.audio_session.**

