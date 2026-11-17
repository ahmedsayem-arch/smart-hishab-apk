# ==========================================
# 1. Flutter Core Wrapper Rules
# ==========================================
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }

# ==========================================
# 2. flutter_local_notifications & Scheduled Alarms
# ==========================================
-keep class com.dexterous.** { *; }
-keepclassmembers class * {
    @androidx.annotation.Keep <fields>;
    @androidx.annotation.Keep <methods>;
}
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses

# ==========================================
# 3. sqflite (SQLite Database) Rules
# ==========================================
-keep class com.tekartik.sqflite.** { *; }

# ==========================================
# 4. AndroidX & General Safety Rules
# ==========================================
-keep class androidx.** { *; }
-dontwarn androidx.**
-dontwarn org.slf4j.**
