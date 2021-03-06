// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library fasta.target_implementation;

import 'package:kernel/target/vm.dart' show VmTarget;

import 'builder/builder.dart' show Builder, ClassBuilder, LibraryBuilder;

import 'loader.dart' show Loader;

import 'target.dart' show Target;

import 'ticker.dart' show Ticker;

import 'translate_uri.dart' show TranslateUri;

/// Provides the implementation details used by a loader for a target.
abstract class TargetImplementation extends Target {
  final TranslateUri uriTranslator;
  Builder cachedCompileTimeError;
  Builder cachedNativeAnnotation;

  TargetImplementation(Ticker ticker, this.uriTranslator) : super(ticker);

  /// Creates a [LibraryBuilder] corresponding to [uri], if one doesn't exist
  /// already.
  LibraryBuilder createLibraryBuilder(Uri uri, Uri fileUri);

  /// Add the classes extended or implemented directly by [cls] to [set].
  void addDirectSupertype(ClassBuilder cls, Set<ClassBuilder> set);

  /// Returns all classes that will be included in the resulting program.
  List<ClassBuilder> collectAllClasses();

  /// The class [cls] is involved in a cyclic definition. This method should
  /// ensure that the cycle is broken, for example, by removing superclass and
  /// implemented interfaces.
  void breakCycle(ClassBuilder cls);

  Uri translateUri(Uri uri) => uriTranslator.translate(uri);

  /// Returns a reference to the constructor used for creating a compile-time
  /// error. The constructor is expected to accept a single argument of type
  /// String, which is the compile-time error message.
  Builder getCompileTimeError(Loader loader) {
    if (cachedCompileTimeError != null) return cachedCompileTimeError;
    return cachedCompileTimeError =
        loader.coreLibrary.getConstructor("_CompileTimeError", isPrivate: true);
  }

  /// Returns a reference to the constructor used for creating `native`
  /// annotations. The constructor is expected to accept a single argument of
  /// type String, which is the name of the native method.
  Builder getNativeAnnotation(Loader loader) {
    if (cachedNativeAnnotation != null) return cachedNativeAnnotation;
    LibraryBuilder internal = loader.read(Uri.parse("dart:_internal"));
    return cachedNativeAnnotation = internal.getConstructor("ExternalName");
  }

  void loadExtraRequiredLibraries(Loader loader) {
    for (String uri in new VmTarget(null).extraRequiredLibraries) {
      loader.read(Uri.parse(uri));
    }
  }

  void addLineStarts(Uri uri, List<int> lineStarts);
}
