// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library fasta.scanner.token;

import 'keyword.dart' show Keyword;

import 'precedence.dart' show BAD_INPUT_INFO, EOF_INFO, PrecedenceInfo;

import 'token_constants.dart' show IDENTIFIER_TOKEN;

import 'string_canonicalizer.dart';

/**
 * A token that doubles as a linked list.
 */
abstract class Token {
  /**
   * The character offset of the start of this token within the source text.
   */
  final int charOffset;

  Token(this.charOffset);

  /**
   * The next token in the token stream.
   */
  Token next;

  /**
   * The precedence info for this token. [info] determines the kind and the
   * precedence level of this token.
   *
   * Defined as getter to save a field in the [KeywordToken] subclass.
   */
  PrecedenceInfo get info;

  /**
   * The string represented by this token, a substring of the source code.
   *
   * For [StringToken]s the [value] includes the quotes, explicit escapes, etc.
   */
  String get value;

  /**
   * For symbol and keyword tokens, returns the string value represented by this
   * token. For [StringToken]s this method returns [:null:].
   *
   * For [SymbolToken]s and [KeywordToken]s, the string value is a compile-time
   * constant originating in the [PrecedenceInfo] or in the [Keyword] instance.
   * This allows testing for keywords and symbols using [:identical:], e.g.,
   * [:identical('class', token.value):].
   *
   * Note that returning [:null:] for string tokens is important to identify
   * symbols and keywords, we cannot use [value] instead. The string literal
   *   "$a($b"
   * produces ..., SymbolToken($), StringToken(a), StringToken((), ...
   *
   * After parsing the identifier 'a', the parser tests for a function
   * declaration using [:identical(next.stringValue, '('):], which (rightfully)
   * returns false because stringValue returns [:null:].
   */
  String get stringValue;

  /**
   * The kind enum of this token as determined by its [info].
   */
  int get kind => info.kind;

  /**
   * The precedence level for this token.
   */
  int get precedence => info.precedence;

  /**
   * True if this token is an identifier. Some keywords allowed as identifiers,
   * see implementation in [KeywordToken].
   */
  bool isIdentifier();

  /**
   * Returns a textual representation of this token to be used for debugging
   * purposes. The resulting string might contain information about the
   * structure of the token, for example 'StringToken(foo)' for the identifier
   * token 'foo'.
   *
   * Use [value] for the text actually parsed by the token.
   */
  String toString();

  /**
   * The number of characters parsed by this token.
   */
  int get charCount {
    if (info == BAD_INPUT_INFO) {
      // This is a token that wraps around an error message. Return 1
      // instead of the size of the length of the error message.
      return 1;
    } else {
      return value.length;
    }
  }

  /// The character offset of the end of this token within the source text.
  int get charEnd => charOffset + charCount;

  bool get isEof => false;
}

/**
 * A [SymbolToken] represents the symbol in its precedence info.
 * Also used for end of file with EOF_INFO.
 */
class SymbolToken extends Token {
  final PrecedenceInfo info;

  SymbolToken(this.info, int charOffset) : super(charOffset);

  String get value => info.value;

  String get stringValue => info.value;

  bool isIdentifier() => false;

  String toString() => "SymbolToken($value)";

  bool get isEof => info == EOF_INFO;
}

/**
 * A [BeginGroupToken] represents a symbol that may be the beginning of
 * a pair of brackets, i.e., ( { [ < or ${
 * The [endGroup] token points to the matching closing bracked in case
 * it can be identified during scanning.
 */
class BeginGroupToken extends SymbolToken {
  Token endGroup;

  BeginGroupToken(PrecedenceInfo info, int charOffset)
      : super(info, charOffset);
}

/**
 * A keyword token.
 */
class KeywordToken extends Token {
  final Keyword keyword;

  KeywordToken(this.keyword, int charOffset) : super(charOffset);

  PrecedenceInfo get info => keyword.info;

  String get value => keyword.syntax;

  String get stringValue => keyword.syntax;

  bool isIdentifier() => keyword.isPseudo || keyword.isBuiltIn;

  String toString() => "KeywordToken($value)";
}

/**
 * A String-valued token. Represents identifiers, string literals,
 * number literals, comments, and error tokens, using the corresponding
 * precedence info.
 */
class StringToken extends Token {
  /**
   * The length threshold above which substring tokens are computed lazily.
   *
   * For string tokens that are substrings of the program source, the actual
   * substring extraction is performed lazily. This is beneficial because
   * not all scanned code is actually used. For unused parts, the substrings
   * are never computed and allocated.
   */
  static const int LAZY_THRESHOLD = 4;

  var /* String | LazySubtring */ valueOrLazySubstring;

  final PrecedenceInfo info;

  /**
   * Creates a non-lazy string token. If [canonicalize] is true, the string
   * is canonicalized before the token is created.
   */
  StringToken.fromString(this.info, String value, int charOffset,
      {bool canonicalize: false})
      : valueOrLazySubstring =
            canonicalizedString(value, 0, value.length, canonicalize),
        super(charOffset);

  /**
   * Creates a lazy string token. If [canonicalize] is true, the string
   * is canonicalized before the token is created.
   */
  StringToken.fromSubstring(
      this.info, String data, int start, int end, int charOffset,
      {bool canonicalize: false})
      : super(charOffset) {
    int length = end - start;
    if (length <= LAZY_THRESHOLD) {
      valueOrLazySubstring =
          canonicalizedString(data, start, end, canonicalize);
    } else {
      valueOrLazySubstring =
          new LazySubstring(data, start, length, canonicalize);
    }
  }

  /**
   * Creates a lazy string token. If [asciiOnly] is false, the byte array
   * is passed through a UTF-8 decoder.
   */
  StringToken.fromUtf8Bytes(this.info, List<int> data, int start, int end,
      bool asciiOnly, int charOffset)
      : super(charOffset) {
    int length = end - start;
    if (length <= LAZY_THRESHOLD) {
      valueOrLazySubstring = decodeUtf8(data, start, end, asciiOnly);
    } else {
      valueOrLazySubstring = new LazySubstring(data, start, length, asciiOnly);
    }
  }

  String get value {
    if (valueOrLazySubstring is String) {
      return valueOrLazySubstring;
    } else {
      assert(valueOrLazySubstring is LazySubstring);
      var data = valueOrLazySubstring.data;
      int start = valueOrLazySubstring.start;
      int end = start + valueOrLazySubstring.length;
      if (data is String) {
        valueOrLazySubstring = canonicalizedString(
            data, start, end, valueOrLazySubstring.boolValue);
      } else {
        valueOrLazySubstring =
            decodeUtf8(data, start, end, valueOrLazySubstring.boolValue);
      }
      return valueOrLazySubstring;
    }
  }

  /// See [Token.stringValue] for an explanation.
  String get stringValue => null;

  bool isIdentifier() => identical(kind, IDENTIFIER_TOKEN);

  String toString() => "StringToken($value)";

  static final StringCanonicalizer canonicalizer = new StringCanonicalizer();

  static String canonicalizedString(
      String s, int start, int end, bool canonicalize) {
    if (!canonicalize) return s;
    return canonicalizer.canonicalize(s, start, end, false);
  }

  static String decodeUtf8(List<int> data, int start, int end, bool asciiOnly) {
    return canonicalizer.canonicalize(data, start, end, asciiOnly);
  }
}

/**
 * This class represents the necessary information to compute a substring
 * lazily. The substring can either originate from a string or from
 * a [:List<int>:] of UTF-8 bytes.
 */
abstract class LazySubstring {
  /** The original data, either a string or a List<int> */
  get data;

  int get start;
  int get length;

  /**
   * If this substring is based on a String, the [boolValue] indicates wheter
   * the resulting substring should be canonicalized.
   *
   * For substrings based on a byte array, the [boolValue] is true if the
   * array only holds ASCII characters. The resulting substring will be
   * canonicalized after decoding.
   */
  bool get boolValue;

  LazySubstring.internal();

  factory LazySubstring(data, int start, int length, bool b) {
    // See comment on [CompactLazySubstring].
    if (start < 0x100000 && length < 0x200) {
      int fields = (start << 9);
      fields = fields | length;
      fields = fields << 1;
      if (b) fields |= 1;
      return new CompactLazySubstring(data, fields);
    } else {
      return new FullLazySubstring(data, start, length, b);
    }
  }
}

/**
 * This class encodes [start], [length] and [boolValue] in a single
 * 30 bit integer. It uses 20 bits for [start], which covers source files
 * of 1MB. [length] has 9 bits, which covers 512 characters.
 *
 * The file html_dart2js.dart is currently around 1MB.
 */
class CompactLazySubstring extends LazySubstring {
  final data;
  final int fields;

  CompactLazySubstring(this.data, this.fields) : super.internal();

  int get start => fields >> 10;
  int get length => (fields >> 1) & 0x1ff;
  bool get boolValue => (fields & 1) == 1;
}

class FullLazySubstring extends LazySubstring {
  final data;
  final int start;
  final int length;
  final bool boolValue;
  FullLazySubstring(this.data, this.start, this.length, this.boolValue)
      : super.internal();
}

bool isUserDefinableOperator(String value) {
  return isBinaryOperator(value) ||
      isMinusOperator(value) ||
      isTernaryOperator(value) ||
      isUnaryOperator(value);
}

bool isUnaryOperator(String value) => identical(value, "~");

bool isBinaryOperator(String value) {
  return identical(value, "==") ||
      identical(value, "[]") ||
      identical(value, "*") ||
      identical(value, "/") ||
      identical(value, "%") ||
      identical(value, "~/") ||
      identical(value, "+") ||
      identical(value, "<<") ||
      identical(value, ">>") ||
      identical(value, ">=") ||
      identical(value, ">") ||
      identical(value, "<=") ||
      identical(value, "<") ||
      identical(value, "&") ||
      identical(value, "^") ||
      identical(value, "|");
}

bool isTernaryOperator(String value) => identical(value, "[]=");

bool isMinusOperator(String value) => identical(value, "-");
