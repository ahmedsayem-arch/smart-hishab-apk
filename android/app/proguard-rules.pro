# ==========================================
# 1. Flutter Core Wrapper Rules
# ==========================================
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn com.google.android.play.core.**

# ==========================================
# 2. flutter_local_notifications & Gson (Fixes Missing type parameter)
# ==========================================
-keep class com.dexterous.** { *; }
-keepclassmembers class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-keep class * extends com.google.gson.reflect.TypeToken { *; }
-keepclassmembers class * extends com.google.gson.reflect.TypeToken { *; }
-keepclassmembers class * {
    @androidx.annotation.Keep <fields>;
    @androidx.annotation.Keep <methods>;
}
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod
-dontwarn sun.misc.Unsafe
-dontwarn javax.annotation.**

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
