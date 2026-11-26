# Keep Java metadata & annotations
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# Flutter & Engine rules
-keep class io.flutter.** { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class com.solderlab.app.** { *; }

# Sqflite & SQLite rules
-keep class com.tekartik.sqflite.** { *; }
-keep class io.requery.android.database.** { *; }

# JNI & Native FFI rules
-keep class com.github.dart_lang.jni.** { *; }

# CameraX & Lifecycle rules
-keep class androidx.camera.** { *; }
-keep class androidx.lifecycle.** { *; }
-keep class io.flutter.plugins.camera.** { *; }
-keep class io.flutter.plugins.camerax.** { *; }

# Suppress non-critical R8 library warnings
-dontwarn io.flutter.embedding.**
-dontwarn androidx.camera.**
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
