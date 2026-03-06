#!/bin/bash
# Source of truth for TextEdit default behavior.

macos_textedit_settings_entries() {
  cat <<'SETTINGS'
com.apple.TextEdit|RichText|bool|0
com.apple.TextEdit|PlainTextEncoding|int|4
com.apple.TextEdit|PlainTextEncodingForWrite|int|4
com.apple.TextEdit|CheckSpellingWhileTyping|bool|0
com.apple.TextEdit|CheckGrammarWithSpelling|bool|0
com.apple.TextEdit|CorrectSpellingAutomatically|bool|0
SETTINGS
}
