# R8 rules for tela's release build.
#
# Flutter, and every plugin here, ship their own consumer rules — R8 reads those
# automatically, so this file carries only what tela itself needs on top. Keep it
# that way: a keep rule copied "just in case" is a class that can never be
# stripped, which is the opposite of why R8 is turned on.

# The method-channel handlers are reached from Dart by channel *name*, never by a
# Java/Kotlin reference, so nothing in the app points at them and R8 cannot see
# they are used. Losing one presents as a plugin that silently stops answering:
# no wallpaper applied, no private listing, no share.
-keep class cc.pym.tela.** { *; }

# WorkManager's database, for auto-rotate.
#
# **This is a crash-on-launch rule, not a defensive one.** WorkManager
# initializes at *process start* through `androidx.startup.Initialization-
# Provider`, and its first act is to reflect a no-arg constructor on Room's
# generated `WorkDatabase_Impl`. R8's full mode — the default from AGP 8 —
# strips that constructor because nothing in the code calls it by name, so the
# release build dies before any Dart runs:
#
#   java.lang.RuntimeException: Unable to get provider
#     androidx.startup.InitializationProvider
#   Caused by: NoSuchMethodException:
#     androidx.work.impl.WorkDatabase_Impl.<init> []
#
# Debug builds are unaffected (no R8), and both suites stay green, so nothing
# short of installing the release build finds it — which is exactly how it was
# found, on the owner's device, 2026-08-26.
#
# Kept narrowly — the constructors, not the classes' contents — but **without
# `allowshrinking`**, which was the first attempt and does not work: it tells R8
# the member may be removed if it looks unused, and a constructor reached only
# by reflection always looks unused. The crash was identical with it.
-keep class * extends androidx.room.RoomDatabase {
    <init>();
}

# Room reads these off the generated implementation by reflection too, and
# stripping them fails the same way one step later.
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-dontwarn androidx.room.paging.**
