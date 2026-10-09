//! Outbound tool-result images: decode, filename, and `m.image` event content.
//!
//! Upload and encryption live on the gateway; this module is the pure JSON/bytes
//! shape so unit tests can pin plaintext `url` vs encrypted `file` without a homeserver.

use lvz_protocol::ToolImage;
use serde_json::{json, Value};

/// Filename for an `m.image` body (`{tool}.jpg`, …).
pub(crate) fn image_filename(tool_name: &str, media_type: &str) -> String {
    let ext = match media_type {
        "image/jpeg" | "image/jpg" => "jpg",
        "image/png" => "png",
        "image/gif" => "gif",
        "image/webp" => "webp",
        _ => "bin",
    };
    format!("{}.{ext}", crate::sanitize_component(tool_name))
}

/// Decode a tool image's base64 payload. `None` if it does not decode (never slices).
pub(crate) fn decode_tool_image(image: &ToolImage) -> Option<Vec<u8>> {
    decode_base64(&image.data)
}

fn decode_base64(input: &str) -> Option<Vec<u8>> {
    let s: String = input.chars().filter(|c| !c.is_whitespace()).collect();
    if s.is_empty() {
        return None;
    }
    let mut padded = s;
    match padded.len() % 4 {
        0 => {}
        2 => padded.push_str("=="),
        3 => padded.push('='),
        _ => return None,
    }
    base64::Engine::decode(
        &base64::engine::general_purpose::STANDARD,
        padded.as_bytes(),
    )
    .ok()
}

/// Unencrypted `m.image` content: `url` is the mxc from the media repo.
pub(crate) fn plaintext_image_content(
    filename: &str,
    mxc: &str,
    media_type: &str,
    size: usize,
) -> Value {
    json!({
        "msgtype": "m.image",
        "body": filename,
        "url": mxc,
        "info": { "mimetype": media_type, "size": size }
    })
}

/// Encrypted-room `m.image` content: `file` is the Matrix EncryptedFile v2 object (url already set).
#[cfg_attr(not(feature = "e2ee"), allow(dead_code))]
pub(crate) fn encrypted_image_content(
    filename: &str,
    file: Value,
    media_type: &str,
    size: usize,
) -> Value {
    json!({
        "msgtype": "m.image",
        "body": filename,
        "file": file,
        "info": { "mimetype": media_type, "size": size }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn image_filename_uses_jpeg_extension() {
        assert_eq!(
            image_filename("server_poll_wake", "image/jpeg"),
            "server_poll_wake.jpg"
        );
    }

    #[test]
    fn decode_skips_undecodable_payloads() {
        let bad = ToolImage {
            media_type: "image/jpeg".into(),
            data: "@@@not-base64@@@".into(),
        };
        assert!(decode_tool_image(&bad).is_none());
        let ok = ToolImage {
            media_type: "image/jpeg".into(),
            data: "YWJjZA==".into(), // "abcd"
        };
        assert_eq!(decode_tool_image(&ok).as_deref(), Some(b"abcd".as_slice()));
    }

    #[test]
    fn plaintext_image_event_uses_mxc_url() {
        let c = plaintext_image_content("wake.jpg", "mxc://hs/abc", "image/jpeg", 12);
        assert_eq!(c["msgtype"], "m.image");
        assert_eq!(c["body"], "wake.jpg");
        assert_eq!(c["url"], "mxc://hs/abc");
        assert_eq!(c["info"]["mimetype"], "image/jpeg");
        assert_eq!(c["info"]["size"], 12);
        assert!(c.get("file").is_none());
    }

    #[test]
    fn encrypted_image_event_uses_file_object() {
        let file = json!({
            "v": "v2",
            "url": "mxc://hs/abc",
            "key": {
                "kty": "oct",
                "key_ops": ["encrypt", "decrypt"],
                "alg": "A256CTR",
                "k": "dGVzdGtleQ",
                "ext": true
            },
            "iv": "AAAAAAAAAAA",
            "hashes": { "sha256": "abcd" }
        });
        let c = encrypted_image_content("wake.jpg", file, "image/jpeg", 12);
        assert_eq!(c["msgtype"], "m.image");
        assert_eq!(c["body"], "wake.jpg");
        assert!(c.get("url").is_none());
        assert_eq!(c["file"]["v"], "v2");
        assert_eq!(c["file"]["url"], "mxc://hs/abc");
        assert_eq!(c["file"]["key"]["alg"], "A256CTR");
        assert_eq!(c["info"]["mimetype"], "image/jpeg");
        assert_eq!(c["info"]["size"], 12);
    }
}
