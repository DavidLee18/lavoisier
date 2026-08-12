//! Lightweight terminal markdown: an inline styler (`**bold**`, `*italic*`/`_italic_`, `` `code` ``,
//! `~~strike~~`) plus a width-aware wrapper for styled segments. Hand-rolled (no `pulldown-cmark`) —
//! it only needs the inline subset, applied per line, so block structure (headings, fenced code) is
//! handled by the caller's line classifier.

use ratatui::style::{Color, Modifier, Style};
use unicode_width::UnicodeWidthStr;

/// A run of text with a resolved style.
pub type Segment = (String, Style);

/// The first index `>= from` at which `needle` occurs in `chars` (single char).
fn find(chars: &[char], from: usize, needle: char) -> Option<usize> {
    (from..chars.len()).find(|&i| chars[i] == needle)
}

/// The first index `>= from` at which the two-char `a b` sequence occurs.
fn find2(chars: &[char], from: usize, a: char, b: char) -> Option<usize> {
    (from..chars.len().saturating_sub(1)).find(|&i| chars[i] == a && chars[i + 1] == b)
}

/// Parse one line's inline markdown into styled segments. An unterminated marker is treated as
/// literal text (so stray `*` or backticks never eat the rest of the line).
pub fn inline(line: &str) -> Vec<Segment> {
    let base = Style::default();
    let chars: Vec<char> = line.chars().collect();
    let mut out: Vec<Segment> = Vec::new();
    let mut plain = String::new();
    let mut i = 0;
    macro_rules! flush {
        () => {
            if !plain.is_empty() {
                out.push((std::mem::take(&mut plain), base));
            }
        };
    }
    while i < chars.len() {
        let c = chars[i];
        // `code`
        if c == '`' {
            if let Some(close) = find(&chars, i + 1, '`') {
                flush!();
                out.push((
                    chars[i + 1..close].iter().collect(),
                    Style::default().fg(Color::Cyan),
                ));
                i = close + 1;
                continue;
            }
        }
        // **bold**
        if c == '*' && chars.get(i + 1) == Some(&'*') {
            if let Some(close) = find2(&chars, i + 2, '*', '*') {
                flush!();
                out.push((
                    chars[i + 2..close].iter().collect(),
                    base.add_modifier(Modifier::BOLD),
                ));
                i = close + 2;
                continue;
            }
        }
        // ~~strike~~
        if c == '~' && chars.get(i + 1) == Some(&'~') {
            if let Some(close) = find2(&chars, i + 2, '~', '~') {
                flush!();
                out.push((
                    chars[i + 2..close].iter().collect(),
                    base.add_modifier(Modifier::CROSSED_OUT),
                ));
                i = close + 2;
                continue;
            }
        }
        // *italic* or _italic_
        if (c == '*' || c == '_') && chars.get(i + 1).is_some_and(|n| !n.is_whitespace()) {
            if let Some(close) = find(&chars, i + 1, c) {
                flush!();
                out.push((
                    chars[i + 1..close].iter().collect(),
                    base.add_modifier(Modifier::ITALIC),
                ));
                i = close + 1;
                continue;
            }
        }
        plain.push(c);
        i += 1;
    }
    flush!();
    if out.is_empty() {
        out.push((String::new(), base));
    }
    out
}

/// Greedily wrap styled segments to `width` display columns, splitting a run mid-way when needed and
/// coalescing consecutive same-style characters into one span per row.
pub fn wrap(segments: &[Segment], width: usize) -> Vec<Vec<Segment>> {
    let width = width.max(1);
    let mut rows: Vec<Vec<Segment>> = vec![Vec::new()];
    let mut col = 0usize;
    for (text, style) in segments {
        for ch in text.chars() {
            let cw = UnicodeWidthStr::width(ch.to_string().as_str()).max(1);
            if col + cw > width && col > 0 {
                rows.push(Vec::new());
                col = 0;
            }
            let row = rows.last_mut().expect("at least one row");
            match row.last_mut() {
                Some((s, st)) if *st == *style => s.push(ch),
                _ => row.push((ch.to_string(), *style)),
            }
            col += cw;
        }
    }
    rows
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn inline_styles_bold_italic_and_code() {
        let segs = inline("a **b** c `d` _e_");
        // Reconstruct the text to confirm markers are consumed, not literal.
        let text: String = segs.iter().map(|(t, _)| t.as_str()).collect();
        assert_eq!(text, "a b c d e");
        assert!(segs
            .iter()
            .any(|(t, s)| t == "b" && s.add_modifier.contains(Modifier::BOLD)));
        assert!(segs
            .iter()
            .any(|(t, s)| t == "d" && s.fg == Some(Color::Cyan)));
        assert!(segs
            .iter()
            .any(|(t, s)| t == "e" && s.add_modifier.contains(Modifier::ITALIC)));
    }

    #[test]
    fn unterminated_marker_stays_literal() {
        let segs = inline("2 * 3 = 6");
        let text: String = segs.iter().map(|(t, _)| t.as_str()).collect();
        assert_eq!(text, "2 * 3 = 6");
        assert!(segs
            .iter()
            .all(|(_, s)| !s.add_modifier.contains(Modifier::ITALIC)));
    }

    #[test]
    fn wrap_splits_and_preserves_style() {
        let segs = vec![("abcdef".to_string(), Style::default())];
        let rows = wrap(&segs, 3);
        assert_eq!(rows.len(), 2);
        let r0: String = rows[0].iter().map(|(t, _)| t.as_str()).collect();
        assert_eq!(r0, "abc");
    }
}
