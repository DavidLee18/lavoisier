/// The definition `page.rs` actually imports.
pub fn render(doc: &Document) -> String {
    let mut out = String::new();
    for node in doc.nodes.iter() {
        out.push_str(&escape(node.text.as_str()));
        out.push('\n');
    }
    out
}

pub fn escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '&' => out.push_str("&amp;"),
            _ => out.push(c),
        }
    }
    out
}
