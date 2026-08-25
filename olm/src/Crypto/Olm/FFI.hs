{-# LANGUAGE CApiFFI #-}

{- | Raw @foreign import@ declarations for libolm, plus the opaque object types. The safe,
'Data.ByteString.ByteString'-based API lives in "Crypto.Olm"; nothing here allocates or frees.

Every libolm call returns @size_t@; on failure it returns @olm_error()@ (= @SIZE_MAX@ =
@maxBound :: CSize@), and a per-object @*_last_error@ gives a human string. Buffer-producing calls
pair a @*_length@ sizing function with the writer. Some calls (@decrypt@, @matches_inbound@,
@create_inbound@, @group_decrypt@, @import@) __overwrite__ their input buffer, so the wrappers copy
inputs into fresh memory first.
-}
module Crypto.Olm.FFI where

import Data.Word (Word32)
import Foreign.C.String (CString)
import Foreign.C.Types (CInt (..), CSize (..))
import Foreign.Ptr (Ptr)

data OlmAccount

data OlmSession

data OlmUtility

data OlmInboundGroupSession

data OlmOutboundGroupSession

-- --- account ---------------------------------------------------------------------------------------

foreign import ccall unsafe "olm_account_size" olm_account_size ∷ IO CSize

foreign import ccall unsafe "olm_account" olm_account ∷ Ptr () → IO (Ptr OlmAccount)

foreign import ccall unsafe "olm_clear_account" olm_clear_account ∷ Ptr OlmAccount → IO CSize

foreign import ccall unsafe "olm_account_last_error" olm_account_last_error ∷ Ptr OlmAccount → IO CString

foreign import ccall unsafe "olm_create_account_random_length" olm_create_account_random_length ∷ Ptr OlmAccount → IO CSize

foreign import ccall unsafe "olm_create_account" olm_create_account ∷ Ptr OlmAccount → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_account_identity_keys_length" olm_account_identity_keys_length ∷ Ptr OlmAccount → IO CSize

foreign import ccall unsafe "olm_account_identity_keys" olm_account_identity_keys ∷ Ptr OlmAccount → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_account_signature_length" olm_account_signature_length ∷ Ptr OlmAccount → IO CSize

foreign import ccall unsafe "olm_account_sign" olm_account_sign ∷ Ptr OlmAccount → Ptr () → CSize → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_account_one_time_keys_length" olm_account_one_time_keys_length ∷ Ptr OlmAccount → IO CSize

foreign import ccall unsafe "olm_account_one_time_keys" olm_account_one_time_keys ∷ Ptr OlmAccount → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_account_mark_keys_as_published" olm_account_mark_keys_as_published ∷ Ptr OlmAccount → IO CSize

foreign import ccall unsafe "olm_account_max_number_of_one_time_keys" olm_account_max_number_of_one_time_keys ∷ Ptr OlmAccount → IO CSize

foreign import ccall unsafe "olm_account_generate_one_time_keys_random_length" olm_account_generate_one_time_keys_random_length ∷ Ptr OlmAccount → CSize → IO CSize

foreign import ccall unsafe "olm_account_generate_one_time_keys" olm_account_generate_one_time_keys ∷ Ptr OlmAccount → CSize → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_account_generate_fallback_key_random_length" olm_account_generate_fallback_key_random_length ∷ Ptr OlmAccount → IO CSize

foreign import ccall unsafe "olm_account_generate_fallback_key" olm_account_generate_fallback_key ∷ Ptr OlmAccount → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_account_unpublished_fallback_key_length" olm_account_unpublished_fallback_key_length ∷ Ptr OlmAccount → IO CSize

foreign import ccall unsafe "olm_account_unpublished_fallback_key" olm_account_unpublished_fallback_key ∷ Ptr OlmAccount → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_pickle_account_length" olm_pickle_account_length ∷ Ptr OlmAccount → IO CSize

foreign import ccall unsafe "olm_pickle_account" olm_pickle_account ∷ Ptr OlmAccount → Ptr () → CSize → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_unpickle_account" olm_unpickle_account ∷ Ptr OlmAccount → Ptr () → CSize → Ptr () → CSize → IO CSize

-- --- session ---------------------------------------------------------------------------------------

foreign import ccall unsafe "olm_session_size" olm_session_size ∷ IO CSize

foreign import ccall unsafe "olm_session" olm_session ∷ Ptr () → IO (Ptr OlmSession)

foreign import ccall unsafe "olm_clear_session" olm_clear_session ∷ Ptr OlmSession → IO CSize

foreign import ccall unsafe "olm_session_last_error" olm_session_last_error ∷ Ptr OlmSession → IO CString

foreign import ccall unsafe "olm_create_outbound_session_random_length" olm_create_outbound_session_random_length ∷ Ptr OlmSession → IO CSize

foreign import ccall unsafe "olm_create_outbound_session" olm_create_outbound_session ∷ Ptr OlmSession → Ptr OlmAccount → Ptr () → CSize → Ptr () → CSize → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_create_inbound_session" olm_create_inbound_session ∷ Ptr OlmSession → Ptr OlmAccount → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_create_inbound_session_from" olm_create_inbound_session_from ∷ Ptr OlmSession → Ptr OlmAccount → Ptr () → CSize → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_session_id_length" olm_session_id_length ∷ Ptr OlmSession → IO CSize

foreign import ccall unsafe "olm_session_id" olm_session_id ∷ Ptr OlmSession → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_session_has_received_message" olm_session_has_received_message ∷ Ptr OlmSession → IO CInt

foreign import ccall unsafe "olm_matches_inbound_session" olm_matches_inbound_session ∷ Ptr OlmSession → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_matches_inbound_session_from" olm_matches_inbound_session_from ∷ Ptr OlmSession → Ptr () → CSize → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_remove_one_time_keys" olm_remove_one_time_keys ∷ Ptr OlmAccount → Ptr OlmSession → IO CSize

foreign import ccall unsafe "olm_encrypt_message_type" olm_encrypt_message_type ∷ Ptr OlmSession → IO CSize

foreign import ccall unsafe "olm_encrypt_random_length" olm_encrypt_random_length ∷ Ptr OlmSession → IO CSize

foreign import ccall unsafe "olm_encrypt_message_length" olm_encrypt_message_length ∷ Ptr OlmSession → CSize → IO CSize

foreign import ccall unsafe "olm_encrypt" olm_encrypt ∷ Ptr OlmSession → Ptr () → CSize → Ptr () → CSize → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_decrypt_max_plaintext_length" olm_decrypt_max_plaintext_length ∷ Ptr OlmSession → CSize → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_decrypt" olm_decrypt ∷ Ptr OlmSession → CSize → Ptr () → CSize → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_pickle_session_length" olm_pickle_session_length ∷ Ptr OlmSession → IO CSize

foreign import ccall unsafe "olm_pickle_session" olm_pickle_session ∷ Ptr OlmSession → Ptr () → CSize → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_unpickle_session" olm_unpickle_session ∷ Ptr OlmSession → Ptr () → CSize → Ptr () → CSize → IO CSize

-- --- utility ---------------------------------------------------------------------------------------

foreign import ccall unsafe "olm_utility_size" olm_utility_size ∷ IO CSize

foreign import ccall unsafe "olm_utility" olm_utility ∷ Ptr () → IO (Ptr OlmUtility)

foreign import ccall unsafe "olm_clear_utility" olm_clear_utility ∷ Ptr OlmUtility → IO CSize

foreign import ccall unsafe "olm_utility_last_error" olm_utility_last_error ∷ Ptr OlmUtility → IO CString

foreign import ccall unsafe "olm_sha256_length" olm_sha256_length ∷ Ptr OlmUtility → IO CSize

foreign import ccall unsafe "olm_sha256" olm_sha256 ∷ Ptr OlmUtility → Ptr () → CSize → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_ed25519_verify" olm_ed25519_verify ∷ Ptr OlmUtility → Ptr () → CSize → Ptr () → CSize → Ptr () → CSize → IO CSize

-- --- inbound group session (Megolm) ----------------------------------------------------------------

foreign import ccall unsafe "olm_inbound_group_session_size" olm_inbound_group_session_size ∷ IO CSize

foreign import ccall unsafe "olm_inbound_group_session" olm_inbound_group_session ∷ Ptr () → IO (Ptr OlmInboundGroupSession)

foreign import ccall unsafe "olm_clear_inbound_group_session" olm_clear_inbound_group_session ∷ Ptr OlmInboundGroupSession → IO CSize

foreign import ccall unsafe "olm_inbound_group_session_last_error" olm_inbound_group_session_last_error ∷ Ptr OlmInboundGroupSession → IO CString

foreign import ccall unsafe "olm_init_inbound_group_session" olm_init_inbound_group_session ∷ Ptr OlmInboundGroupSession → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_import_inbound_group_session" olm_import_inbound_group_session ∷ Ptr OlmInboundGroupSession → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_group_decrypt_max_plaintext_length" olm_group_decrypt_max_plaintext_length ∷ Ptr OlmInboundGroupSession → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_group_decrypt" olm_group_decrypt ∷ Ptr OlmInboundGroupSession → Ptr () → CSize → Ptr () → CSize → Ptr Word32 → IO CSize

foreign import ccall unsafe "olm_inbound_group_session_id_length" olm_inbound_group_session_id_length ∷ Ptr OlmInboundGroupSession → IO CSize

foreign import ccall unsafe "olm_inbound_group_session_id" olm_inbound_group_session_id ∷ Ptr OlmInboundGroupSession → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_inbound_group_session_first_known_index" olm_inbound_group_session_first_known_index ∷ Ptr OlmInboundGroupSession → IO Word32

foreign import ccall unsafe "olm_export_inbound_group_session_length" olm_export_inbound_group_session_length ∷ Ptr OlmInboundGroupSession → IO CSize

foreign import ccall unsafe "olm_export_inbound_group_session" olm_export_inbound_group_session ∷ Ptr OlmInboundGroupSession → Ptr () → CSize → Word32 → IO CSize

foreign import ccall unsafe "olm_pickle_inbound_group_session_length" olm_pickle_inbound_group_session_length ∷ Ptr OlmInboundGroupSession → IO CSize

foreign import ccall unsafe "olm_pickle_inbound_group_session" olm_pickle_inbound_group_session ∷ Ptr OlmInboundGroupSession → Ptr () → CSize → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_unpickle_inbound_group_session" olm_unpickle_inbound_group_session ∷ Ptr OlmInboundGroupSession → Ptr () → CSize → Ptr () → CSize → IO CSize

-- --- outbound group session (Megolm) ---------------------------------------------------------------

foreign import ccall unsafe "olm_outbound_group_session_size" olm_outbound_group_session_size ∷ IO CSize

foreign import ccall unsafe "olm_outbound_group_session" olm_outbound_group_session ∷ Ptr () → IO (Ptr OlmOutboundGroupSession)

foreign import ccall unsafe "olm_clear_outbound_group_session" olm_clear_outbound_group_session ∷ Ptr OlmOutboundGroupSession → IO CSize

foreign import ccall unsafe "olm_outbound_group_session_last_error" olm_outbound_group_session_last_error ∷ Ptr OlmOutboundGroupSession → IO CString

foreign import ccall unsafe "olm_init_outbound_group_session_random_length" olm_init_outbound_group_session_random_length ∷ Ptr OlmOutboundGroupSession → IO CSize

foreign import ccall unsafe "olm_init_outbound_group_session" olm_init_outbound_group_session ∷ Ptr OlmOutboundGroupSession → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_group_encrypt_message_length" olm_group_encrypt_message_length ∷ Ptr OlmOutboundGroupSession → CSize → IO CSize

foreign import ccall unsafe "olm_group_encrypt" olm_group_encrypt ∷ Ptr OlmOutboundGroupSession → Ptr () → CSize → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_outbound_group_session_id_length" olm_outbound_group_session_id_length ∷ Ptr OlmOutboundGroupSession → IO CSize

foreign import ccall unsafe "olm_outbound_group_session_id" olm_outbound_group_session_id ∷ Ptr OlmOutboundGroupSession → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_outbound_group_session_message_index" olm_outbound_group_session_message_index ∷ Ptr OlmOutboundGroupSession → IO Word32

foreign import ccall unsafe "olm_outbound_group_session_key_length" olm_outbound_group_session_key_length ∷ Ptr OlmOutboundGroupSession → IO CSize

foreign import ccall unsafe "olm_outbound_group_session_key" olm_outbound_group_session_key ∷ Ptr OlmOutboundGroupSession → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_pickle_outbound_group_session_length" olm_pickle_outbound_group_session_length ∷ Ptr OlmOutboundGroupSession → IO CSize

foreign import ccall unsafe "olm_pickle_outbound_group_session" olm_pickle_outbound_group_session ∷ Ptr OlmOutboundGroupSession → Ptr () → CSize → Ptr () → CSize → IO CSize

foreign import ccall unsafe "olm_unpickle_outbound_group_session" olm_unpickle_outbound_group_session ∷ Ptr OlmOutboundGroupSession → Ptr () → CSize → Ptr () → CSize → IO CSize
