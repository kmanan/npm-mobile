# Keep Google API Client
-keep class com.google.api.client.** { *; }
-keep class com.google.api.services.** { *; }
-dontwarn com.google.api.client.**

# Keep Google Error Prone Annotations
-keep class com.google.errorprone.annotations.** { *; }
-dontwarn com.google.errorprone.annotations.**

# Keep Joda Time
-keep class org.joda.time.** { *; }
-dontwarn org.joda.time.**

# Keep Tink Crypto
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**

# Keep Java Annotations
-keep class javax.annotation.** { *; }
-dontwarn javax.annotation.**

# Keep NetHttpTransport
-keep class com.google.api.client.http.** { *; }
-keep class com.google.api.client.http.javanet.** { *; }
-dontwarn com.google.api.client.http.**