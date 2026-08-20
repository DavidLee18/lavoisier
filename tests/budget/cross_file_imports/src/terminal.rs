/// A same-named symbol in an unimported module: the decoy the ranking must not pull in.
pub fn render(doc: &Document) -> String {
    let mut out = String::new();
    for node in doc.nodes.iter() {
        out.push_str(&colorize(node.text.as_str()));
        out.push('\n');
    }
    out
}

pub fn colorize(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 16);
    out.push_str("\x1b[1m");
    for c in s.chars() {
        out.push(c);
    }
    out.push_str("\x1b[0m");
    out
}
