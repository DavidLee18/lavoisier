//! AES-256-GCM pickle codec. The key is HKDF-SHA256 of `MATRIX_CRYPTO_STORE_KEY`.
//! Lookup columns stay outside this codec. Logs must not print the key or the bytes.

use aes_gcm::{
    aead::{Aead, KeyInit},
    Aes256Gcm, Nonce,
};
use hkdf::Hkdf;
use hmac::{Hmac, Mac};
use sha2::Sha256;

use super::error::StoreError;

const INFO: &[u8] = b"lavoisier-crypto-store-v1";
const HMAC_INFO: &[u8] = b"lavoisier-crypto-store-secret-hmac-v1";

/// Seals pickle bytes. The nonce is random per write and stored beside the ciphertext.
pub(crate) struct StoreCodec {
    key: [u8; 32],
    hmac_key: [u8; 32],
}

impl StoreCodec {
    pub(crate) fn from_passphrase(passphrase: &str) -> Result<Self, StoreError> {
        let hk = Hkdf::<Sha256>::new(None, passphrase.as_bytes());
        let mut key = [0u8; 32];
        let mut hmac_key = [0u8; 32];
        hk.expand(INFO, &mut key)
            .map_err(|_| StoreError::Other("hkdf expand failed".into()))?;
        hk.expand(HMAC_INFO, &mut hmac_key)
            .map_err(|_| StoreError::Other("hkdf hmac expand failed".into()))?;
        Ok(Self { key, hmac_key })
    }

    pub(crate) fn seal(&self, plain: &[u8]) -> Result<(Vec<u8>, Vec<u8>), StoreError> {
        let mut nonce = [0u8; 12];
        getrandom::getrandom(&mut nonce).map_err(|e| StoreError::Other(e.to_string()))?;
        let cipher = Aes256Gcm::new_from_slice(&self.key)
            .map_err(|_| StoreError::Other("aes-256-gcm key".into()))?;
        let ct = cipher
            .encrypt(Nonce::from_slice(&nonce), plain)
            .map_err(|_| StoreError::Other("aes-gcm seal failed".into()))?;
        Ok((nonce.to_vec(), ct))
    }

    pub(crate) fn open(&self, nonce: &[u8], ct: &[u8]) -> Result<Vec<u8>, StoreError> {
        if nonce.len() != 12 {
            return Err(StoreError::Unpickle);
        }
        let cipher = Aes256Gcm::new_from_slice(&self.key)
            .map_err(|_| StoreError::Other("aes-256-gcm key".into()))?;
        cipher
            .decrypt(Nonce::from_slice(nonce), ct)
            .map_err(|_| StoreError::Unpickle)
    }

    /// HMAC-SHA256 of a secrets-inbox plaintext. Identical plaintext shares one HMAC.
    pub(crate) fn secret_hmac(&self, secret: &str) -> Result<Vec<u8>, StoreError> {
        let mut mac = <Hmac<Sha256> as Mac>::new_from_slice(&self.hmac_key)
            .map_err(|_| StoreError::Other("hmac key".into()))?;
        mac.update(secret.as_bytes());
        Ok(mac.finalize().into_bytes().to_vec())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn seal_roundtrips_and_nonce_changes() {
        let codec = StoreCodec::from_passphrase("test-passphrase").unwrap();
        let (n1, c1) = codec.seal(b"olm-pickle").unwrap();
        let (n2, _c2) = codec.seal(b"olm-pickle").unwrap();
        assert_ne!(n1, n2);
        assert_eq!(codec.open(&n1, &c1).unwrap(), b"olm-pickle");
        assert!(codec.open(&n2, &c1).is_err());
        let h1 = codec.secret_hmac("same").unwrap();
        let h2 = codec.secret_hmac("same").unwrap();
        assert_eq!(h1, h2);
        assert_ne!(h1, codec.secret_hmac("other").unwrap());
    }
}
