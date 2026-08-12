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

// ---------------------------------------------------------------------------------------------
// Tables — a block construct: rows are buffered by the caller, then rendered aligned as a unit.
// ---------------------------------------------------------------------------------------------

/// Column alignment from a table's separator row.
#[derive(Clone, Copy)]
enum Align {
    Left,
    Center,
    Right,
}

/// Display width of a string in terminal columns.
fn disp(s: &str) -> usize {
    UnicodeWidthStr::width(s)
}

/// Whether a line looks like a table row (trimmed, starts with `|`).
pub fn is_table_row(line: &str) -> bool {
    let t = line.trim_start();
    t.starts_with('|') && t.chars().nth(1).is_some()
}

/// Split a `| a | b |` row into trimmed cells, preserving internal empty cells.
fn parse_row(line: &str) -> Vec<String> {
    let t = line.trim();
    let t = t.strip_prefix('|').unwrap_or(t);
    let t = t.strip_suffix('|').unwrap_or(t);
    t.split('|').map(|c| c.trim().to_string()).collect()
}

/// Whether a line is a table *separator* row (`|---|:--:|`): every cell is dashes with optional
/// leading/trailing colons.
fn is_separator_row(line: &str) -> bool {
    let cells = parse_row(line);
    !cells.is_empty()
        && cells.iter().all(|c| {
            let c = c.trim();
            c.contains('-') && c.chars().all(|ch| ch == '-' || ch == ':')
        })
}

/// Per-column alignment parsed from the separator row's colons.
fn parse_aligns(line: &str) -> Vec<Align> {
    parse_row(line)
        .iter()
        .map(|c| {
            let c = c.trim();
            match (c.starts_with(':'), c.ends_with(':')) {
                (true, true) => Align::Center,
                (false, true) => Align::Right,
                _ => Align::Left,
            }
        })
        .collect()
}

/// Truncate `s` to `w` display columns, appending `…` when it doesn't fit.
fn truncate_to_width(s: &str, w: usize) -> String {
    if disp(s) <= w {
        return s.to_string();
    }
    if w == 0 {
        return String::new();
    }
    let mut acc = String::new();
    let mut used = 0;
    for ch in s.chars() {
        let cw = UnicodeWidthStr::width(ch.to_string().as_str()).max(1);
        if used + cw > w - 1 {
            break;
        }
        acc.push(ch);
        used += cw;
    }
    acc.push('…');
    acc
}

/// Pad `s` to `w` display columns per `align` (assumes `s` already fits).
fn pad_to_width(s: &str, w: usize, align: Align) -> String {
    let d = disp(s);
    if d >= w {
        return s.to_string();
    }
    let pad = w - d;
    match align {
        Align::Right => format!("{}{}", " ".repeat(pad), s),
        Align::Left => format!("{}{}", s, " ".repeat(pad)),
        Align::Center => {
            let l = pad / 2;
            format!("{}{}{}", " ".repeat(l), s, " ".repeat(pad - l))
        }
    }
}

/// Shrink column widths (widest first) until the row fits `avail`, so a wide table truncates cells
/// rather than overflowing the terminal.
fn fit_widths(widths: &mut [usize], avail: usize) {
    let seps = 3 * widths.len().saturating_sub(1);
    let budget = avail.saturating_sub(seps).max(widths.len());
    while widths.iter().sum::<usize>() > budget {
        let (idx, max) = widths
            .iter()
            .enumerate()
            .max_by_key(|(_, w)| **w)
            .map(|(i, w)| (i, *w))
            .unwrap();
        if max <= 3 {
            break;
        }
        widths[idx] -= 1;
    }
}

/// The `i`th cell of a row, or "" when the row is short.
fn nth_cell(row: &[String], i: usize) -> &str {
    row.get(i).map(String::as_str).unwrap_or("")
}

/// Render buffered table lines into aligned, styled visual rows (header bold, a `─┼─` rule, then
/// data), fitted to `width`. Returns `None` when the lines aren't a valid table (no separator row),
/// so the caller can fall back to plain rendering.
pub fn render_table(lines: &[String], width: usize) -> Option<Vec<Vec<Segment>>> {
    if lines.len() < 2 || !is_separator_row(&lines[1]) {
        return None;
    }
    let header = parse_row(&lines[0]);
    let aligns = parse_aligns(&lines[1]);
    let data: Vec<Vec<String>> = lines[2..].iter().map(|l| parse_row(l)).collect();
    let ncols = header
        .len()
        .max(data.iter().map(Vec::len).max().unwrap_or(0))
        .max(1);

    let mut widths = vec![1usize; ncols];
    for (i, w) in widths.iter_mut().enumerate() {
        *w = disp(nth_cell(&header, i));
        for row in &data {
            *w = (*w).max(disp(nth_cell(row, i)));
        }
        *w = (*w).max(1);
    }
    fit_widths(&mut widths, width);

    let sep = Style::default().fg(Color::DarkGray);
    let align = |i: usize| *aligns.get(i).unwrap_or(&Align::Left);
    let build = |row: &[String], style: Style| -> Vec<Segment> {
        let mut out = Vec::new();
        for (i, &w) in widths.iter().enumerate() {
            if i > 0 {
                out.push((" │ ".to_string(), sep));
            }
            let fitted = truncate_to_width(nth_cell(row, i), w);
            out.push((pad_to_width(&fitted, w, align(i)), style));
        }
        out
    };

    let mut out = Vec::new();
    out.push(build(
        &header,
        Style::default().add_modifier(Modifier::BOLD),
    ));
    let mut rule = Vec::new();
    for (i, w) in widths.iter().enumerate() {
        if i > 0 {
            rule.push(("─┼─".to_string(), sep));
        }
        rule.push(("─".repeat(*w), sep));
    }
    out.push(rule);
    for row in &data {
        out.push(build(row, Style::default()));
    }
    Some(out)
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

    #[test]
    fn detects_table_and_separator_rows() {
        assert!(is_table_row("| a | b |"));
        assert!(is_table_row("  |x|"));
        assert!(!is_table_row("just text"));
        assert!(is_separator_row("|---|:--:|"));
        assert!(is_separator_row("| :-- | --: |"));
        assert!(!is_separator_row("| a | b |"));
    }

    #[test]
    fn renders_an_aligned_table() {
        let lines = vec![
            "| Name | Score |".to_string(),
            "|------|------:|".to_string(),
            "| alice | 3 |".to_string(),
            "| bob | 100 |".to_string(),
        ];
        let rows = render_table(&lines, 80).expect("valid table");
        // header + rule + 2 data rows.
        assert_eq!(rows.len(), 4);
        // Header cells are bold.
        assert!(rows[0]
            .iter()
            .any(|(t, s)| t.contains("Name") && s.add_modifier.contains(Modifier::BOLD)));
        // The rule row is drawn with box characters.
        let rule: String = rows[1].iter().map(|(t, _)| t.as_str()).collect();
        assert!(rule.contains('─') && rule.contains('┼'));
        // Right-aligned Score column pads on the left ("  3").
        let alice: String = rows[2].iter().map(|(t, _)| t.as_str()).collect();
        assert!(alice.contains("  3"), "right-aligned, got {alice:?}");
    }

    #[test]
    fn non_table_lines_are_rejected() {
        // No separator row ⇒ not a table (caller falls back to plain rendering).
        let lines = vec!["| a | b |".to_string(), "| c | d |".to_string()];
        assert!(render_table(&lines, 80).is_none());
    }

    #[test]
    fn a_too_wide_table_shrinks_to_fit() {
        let lines = vec![
            "| col |".to_string(),
            "|-----|".to_string(),
            format!("| {} |", "x".repeat(200)),
        ];
        let rows = render_table(&lines, 40).unwrap();
        for row in &rows {
            let w: usize = row.iter().map(|(t, _)| disp(t)).sum();
            assert!(w <= 40, "row exceeded width: {w}");
        }
    }
}
