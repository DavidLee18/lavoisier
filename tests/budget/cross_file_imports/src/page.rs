use crate::html::render;

/// Entry point the fixture edits.
pub fn render_page(doc: &Document) -> String {
    let body = render(doc);
    wrap(body)
}

pub fn wrap(body: String) -> String {
    let mut out = String::with_capacity(body.len() + 64);
    out.push_str("<html><body>");
    out.push_str(&body);
    out.push_str("</body></html>");
    out
}
