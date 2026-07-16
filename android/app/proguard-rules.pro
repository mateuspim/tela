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
