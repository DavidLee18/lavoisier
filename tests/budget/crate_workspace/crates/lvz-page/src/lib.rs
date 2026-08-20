//! The crate holding the edit target.

use lvz_html::render;
use lvz_protocol::Document;

pub fn render_page(doc: &Document) -> String {
    let body = render(doc);
    wrap(&doc.title, body)
}

pub fn wrap(title: &str, body: String) -> String {
    let mut out = String::with_capacity(body.len() + 64);
    out.push_str("<html><head><title>");
    out.push_str(title);
    out.push_str("</title></head><body>");
    out.push_str(&body);
    out.push_str("</body></html>");
    out
}

pub fn render_all(docs: &[Document]) -> Vec<String> {
    docs.iter().map(render_page).collect()
}
