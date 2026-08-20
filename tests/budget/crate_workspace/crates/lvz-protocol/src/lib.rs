//! Shared types. Every crate depends on this one; nothing here is same-named.

pub struct Node {
    pub text: String,
    pub kind: Kind,
}

pub enum Kind {
    Text,
    Heading,
    Code,
}

pub struct Document {
    pub nodes: Vec<Node>,
    pub title: String,
}

impl Document {
    pub fn is_empty(&self) -> bool {
        self.nodes.is_empty()
    }
}

pub fn node_count(doc: &Document) -> usize {
    doc.nodes.len()
}
