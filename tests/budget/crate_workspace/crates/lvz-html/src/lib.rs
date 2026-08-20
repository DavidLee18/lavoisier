//! HTML rendering. `page` imports this one.

use lvz_protocol::{Document, Kind, Node};

pub fn render(doc: &Document) -> String {
    let mut out = String::new();
    for node in &doc.nodes {
        out.push_str(&render_node(node));
        out.push('\n');
    }
    out
}

pub fn render_node(node: &Node) -> String {
    match node.kind {
        Kind::Heading => format!("<h1>{}</h1>", escape(&node.text)),
        Kind::Code => format!("<pre>{}</pre>", escape(&node.text)),
        Kind::Text => format!("<p>{}</p>", escape(&node.text)),
    }
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

pub fn doctype() -> &'static str {
    "<!doctype html>"
}
