import QtQuick
import qs.Commons

// Text in the theme's font and colour: every label in the plugin starts here.
// Plain text by default, because commits and names come from strangers: a
// body that looks like HTML must print as typed, not load an <img>. A label
// that wants markup asks for Text.StyledText and escapes what it interpolates.
Text {
  color: Color.foreground
  font.family: Style.font.family
  font.pixelSize: Style.font.bodySmall
  textFormat: Text.PlainText
}
