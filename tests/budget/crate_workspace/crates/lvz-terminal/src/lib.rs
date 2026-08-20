//! Terminal rendering. Defines `render` and `render_node` too, but `page` does not import it.

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
        Kind::Heading => bold(&node.text),
        Kind::Code => dim(&node.text),
        Kind::Text => node.text.clone(),
    }
}

pub fn bold(s: &str) -> String {
    format!("\x1b[1m{}\x1b[0m", s)
}

pub fn dim(s: &str) -> String {
    format!("\x1b[2m{}\x1b[0m", s)
}
