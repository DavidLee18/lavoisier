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

/// `info` for an `m.image`: always `mimetype` + `size`; JPEG also `w`/`h` from the SOF.
fn image_info(media_type: &str, bytes: &[u8]) -> Value {
    let mut info = json!({ "mimetype": media_type, "size": bytes.len() });
    if matches!(media_type, "image/jpeg" | "image/jpg") {
        if let Some((w, h)) = jpeg_dimensions(bytes) {
            info["w"] = json!(w);
            info["h"] = json!(h);
        }
    }
    info
}

/// Width and height from a JPEG Start-Of-Frame, if the payload is a well-formed JPEG.
fn jpeg_dimensions(bytes: &[u8]) -> Option<(u32, u32)> {
    if bytes.len() < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8 {
        return None;
    }
    let mut i = 2usize;
    while i + 1 < bytes.len() {
        if bytes[i] != 0xFF {
            return None;
        }
        while i < bytes.len() && bytes[i] == 0xFF {
            i += 1;
        }
        if i >= bytes.len() {
            return None;
        }
        let marker = bytes[i];
        i += 1;
        if marker == 0xD8 || marker == 0xD9 || (0xD0..=0xD7).contains(&marker) {
            continue;
        }
        if i + 1 >= bytes.len() {
            return None;
        }
        let len = u16::from_be_bytes([bytes[i], bytes[i + 1]]) as usize;
        if len < 2 || i + len > bytes.len() {
            return None;
        }
        let is_sof = matches!(
            marker,
            0xC0 | 0xC1
                | 0xC2
                | 0xC3
                | 0xC5
                | 0xC6
                | 0xC7
                | 0xC9
                | 0xCA
                | 0xCB
                | 0xCD
                | 0xCE
                | 0xCF
        );
        if is_sof {
            if len < 7 {
                return None;
            }
            let h = u16::from_be_bytes([bytes[i + 3], bytes[i + 4]]) as u32;
            let w = u16::from_be_bytes([bytes[i + 5], bytes[i + 6]]) as u32;
            if w == 0 || h == 0 {
                return None;
            }
            return Some((w, h));
        }
        i += len;
    }
    None
}

/// Unencrypted `m.image` content: `url` is the mxc from the media repo.
pub(crate) fn plaintext_image_content(
    filename: &str,
    mxc: &str,
    media_type: &str,
    bytes: &[u8],
) -> Value {
    json!({
        "msgtype": "m.image",
        "body": filename,
        "url": mxc,
        "info": image_info(media_type, bytes)
    })
}

/// Encrypted-room `m.image` content: `file` is the Matrix EncryptedFile v2 object (url already set).
#[cfg_attr(not(feature = "e2ee"), allow(dead_code))]
pub(crate) fn encrypted_image_content(
    filename: &str,
    file: Value,
    media_type: &str,
    bytes: &[u8],
) -> Value {
    json!({
        "msgtype": "m.image",
        "body": filename,
        "file": file,
        "info": image_info(media_type, bytes)
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

    /// Minimal JPEG: SOI + SOF0 (8-bit, 2×3, one component) + EOI.
    fn tiny_jpeg() -> Vec<u8> {
        vec![
            0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x02, 0x00, 0x03, 0x01, 0x11, 0x00,
            0xFF, 0xD9,
        ]
    }

    #[test]
    fn jpeg_dimensions_reads_sof0() {
        assert_eq!(jpeg_dimensions(&tiny_jpeg()), Some((3, 2)));
        assert_eq!(jpeg_dimensions(b"not a jpeg"), None);
    }

    #[test]
    fn plaintext_image_event_uses_mxc_url() {
        let jpeg = tiny_jpeg();
        let c = plaintext_image_content("wake.jpg", "mxc://hs/abc", "image/jpeg", &jpeg);
        assert_eq!(c["msgtype"], "m.image");
        assert_eq!(c["body"], "wake.jpg");
        assert_eq!(c["url"], "mxc://hs/abc");
        assert_eq!(c["info"]["mimetype"], "image/jpeg");
        assert_eq!(c["info"]["size"], jpeg.len());
        assert_eq!(c["info"]["w"], 3);
        assert_eq!(c["info"]["h"], 2);
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
        let jpeg = tiny_jpeg();
        let c = encrypted_image_content("wake.jpg", file, "image/jpeg", &jpeg);
        assert_eq!(c["msgtype"], "m.image");
        assert_eq!(c["body"], "wake.jpg");
        assert!(c.get("url").is_none());
        assert_eq!(c["file"]["v"], "v2");
        assert_eq!(c["file"]["url"], "mxc://hs/abc");
        assert_eq!(c["file"]["key"]["alg"], "A256CTR");
        assert_eq!(c["info"]["mimetype"], "image/jpeg");
        assert_eq!(c["info"]["size"], jpeg.len());
        assert_eq!(c["info"]["w"], 3);
        assert_eq!(c["info"]["h"], 2);
    }
}
