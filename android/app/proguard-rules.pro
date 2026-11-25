# Flutter & Engine rules
-keep class io.flutter.** { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.embedding.**  { *; }

# Sqflite & SQLite rules
-keep class com.tekartik.sqflite.** { *; }
-keep class io.requery.android.database.** { *; }

# CameraX & Image rules
-keep class androidx.camera.** { *; }
-keep class io.flutter.plugins.camera.** { *; }

# Optimization & Obfuscation
-dontwarn io.flutter.embedding.**
-dontwarn androidx.camera.**
