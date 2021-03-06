// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style licenset hat can be found in the LICENSE file.

library dart_scanner.error_token;

// TODO(ahe): ErrorKind doesn't belong in dart_parser. Move to compiler_util or
// this package?
import '../parser/error_kind.dart' show ErrorKind;

import '../scanner.dart'
    show BeginGroupToken, Token, unicodeReplacementCharacter;

import 'precedence.dart' show BAD_INPUT_INFO, PrecedenceInfo;

export '../parser/error_kind.dart' show ErrorKind;

ErrorToken buildUnexpectedCharacterToken(int character, int charOffset) {
  if (character < 0x1f) {
    return new AsciiControlCharacterToken(character, charOffset);
  }
  switch (character) {
    case unicodeReplacementCharacter:
      return new EncodingErrorToken(charOffset);

    /// See [General Punctuation]
    /// (http://www.unicode.org/charts/PDF/U2000.pdf).
    case 0x00A0: // No-break space.
    case 0x1680: // Ogham space mark.
    case 0x180E: // Mongolian vowel separator.
    case 0x2000: // En quad.
    case 0x2001: // Em quad.
    case 0x2002: // En space.
    case 0x2003: // Em space.
    case 0x2004: // Three-per-em space.
    case 0x2005: // Four-per-em space.
    case 0x2006: // Six-per-em space.
    case 0x2007: // Figure space.
    case 0x2008: // Punctuation space.
    case 0x2009: // Thin space.
    case 0x200A: // Hair space.
    case 0x200B: // Zero width space.
    case 0x2028: // Line separator.
    case 0x2029: // Paragraph separator.
    case 0x202F: // Narrow no-break space.
    case 0x205F: // Medium mathematical space.
    case 0x3000: // Ideographic space.
    case 0xFEFF: // Zero width no-break space.
      return new NonAsciiWhitespaceToken(character, charOffset);

    default:
      return new NonAsciiIdentifierToken(character, charOffset);
  }
}

/// Common superclass for all error tokens.
///
/// It's considered an implementation error to access [value] of an
/// [ErrorToken].
abstract class ErrorToken extends Token {
  ErrorToken(int charOffset) : super(charOffset);

  PrecedenceInfo get info => BAD_INPUT_INFO;

  String get value => throw assertionMessage;

  String get stringValue => null;

  bool isIdentifier() => false;

  String get assertionMessage;

  ErrorKind get errorCode;

  int get character => null;

  String get start => null;

  int get endOffset => null;

  BeginGroupToken get begin => null;
}

/// Represents an encoding error.
class EncodingErrorToken extends ErrorToken {
  EncodingErrorToken(int charOffset) : super(charOffset);

  String toString() => "EncodingErrorToken()";

  String get assertionMessage => "Unable to decode bytes as UTF-8.";

  ErrorKind get errorCode => ErrorKind.Encoding;
}

/// Represents a non-ASCII character outside a string or comment.
class NonAsciiIdentifierToken extends ErrorToken {
  final int character;

  NonAsciiIdentifierToken(this.character, int charOffset) : super(charOffset);

  String toString() => "NonAsciiIdentifierToken($character)";

  String get assertionMessage {
    String c = new String.fromCharCodes([character]);
    String hex = character.toRadixString(16);
    String padding = "0000".substring(hex.length);
    hex = "$padding$hex";
    return "The non-ASCII character '$c' (U+$hex) can't be used in identifiers,"
        " only in strings and comments.\n"
        "Try using an US-ASCII letter, a digit, '_' (an underscore),"
        " or '\$' (a dollar sign).";
  }

  ErrorKind get errorCode => ErrorKind.NonAsciiIdentifier;
}

/// Represents a non-ASCII whitespace outside a string or comment.
class NonAsciiWhitespaceToken extends ErrorToken {
  final int character;

  NonAsciiWhitespaceToken(this.character, int charOffset) : super(charOffset);

  String toString() => "NonAsciiWhitespaceToken($character)";

  String get assertionMessage {
    String hex = character.toRadixString(16);
    return "The non-ASCII space character U+$hex can only be used in strings "
        "and comments.";
  }

  ErrorKind get errorCode => ErrorKind.NonAsciiWhitespace;
}

/// Represents an ASCII control character outside a string or comment.
class AsciiControlCharacterToken extends ErrorToken {
  final int character;

  AsciiControlCharacterToken(this.character, int charOffset)
      : super(charOffset);

  String toString() => "AsciiControlCharacterToken($character)";

  String get assertionMessage {
    String hex = character.toRadixString(16);
    return "The control character U+$hex can only be used in strings and "
        "comments.";
  }

  ErrorKind get errorCode => ErrorKind.AsciiControlCharacter;
}

/// Represents an unterminated string.
class UnterminatedToken extends ErrorToken {
  final String start;
  final int endOffset;

  UnterminatedToken(this.start, int charOffset, this.endOffset)
      : super(charOffset);

  String toString() => "UnterminatedToken($start)";

  String get assertionMessage => "'$start' isn't terminated.";

  int get charCount => endOffset - charOffset;

  ErrorKind get errorCode {
    switch (start) {
      case '1e':
        return ErrorKind.MissingExponent;

      case '"':
      case "'":
      case '"""':
      case "'''":
      case 'r"':
      case "r'":
      case 'r"""':
      case "r'''":
        return ErrorKind.UnterminatedString;

      case '0x':
        return ErrorKind.ExpectedHexDigit;

      case r'$':
        return ErrorKind.UnexpectedDollarInString;

      case '/*':
        return ErrorKind.UnterminatedComment;

      default:
        return ErrorKind.UnterminatedToken;
    }
  }
}

/// Represents an open brace without a matching close brace.
///
/// In this case, brace means any of `(`, `{`, `[`, and `<`, parenthesis, curly
/// brace, square brace, and angle brace, respectively.
class UnmatchedToken extends ErrorToken {
  final BeginGroupToken begin;

  UnmatchedToken(BeginGroupToken begin)
      : this.begin = begin,
        super(begin.charOffset);

  String toString() => "UnmatchedToken(${begin.value})";

  String get assertionMessage => "'$begin' isn't closed.";

  ErrorKind get errorCode => ErrorKind.UnmatchedToken;
}
