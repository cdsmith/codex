{-# language QuasiQuotes #-}
{-# language ViewPatterns #-}
{-# language TemplateHaskell #-}
{-# language PatternSynonyms #-}
{-# language LambdaCase #-}
-- |
module Graphics.Harfbuzz.OpenType
(
-- * @hb-ot.h@
  OpenTypeName(..)
, OpenTypeLayoutGlyphClass(..)
, pattern OT_TAG_BASE
, pattern OT_TAG_GDEF
, pattern OT_TAG_GPOS
, pattern OT_TAG_GSUB
, pattern OT_TAG_JSTF
, pattern OT_TAG_DEFAULT_LANGUAGE
, pattern OT_TAG_DEFAULT_SCRIPT
, ot_layout_collect_features
, ot_layout_collect_lookups
, ot_layout_feature_get_characters
, ot_layout_feature_get_lookups
, ot_tag_to_language
, ot_tag_to_script
, ot_tags_from_script_and_language
, ot_tags_to_script_and_language
-- * @hb-ot-name.h@
, ot_name_list_names
, ot_name_get
-- * @hb-ot-shape.h@
, ot_shape_glyphs_closure
) where

import Control.Monad.IO.Class
import Foreign.Marshal.Alloc
import Foreign.Marshal.Array
import Foreign.Marshal.Unsafe
import Foreign.Marshal.Utils
import Foreign.Ptr
import Foreign.Storable
import qualified Language.C.Inline as C

import Graphics.Harfbuzz.Internal

C.context $ C.baseCtx <> harfbuzzOpenTypeCtx
C.include "<hb.h>"
C.include "<hb-ot.h>"

-- | Fetches a list of all feature-lookup indexes in the specified face's GSUB table or GPOS table, underneath the specified scripts,
-- languages, and features. If no list of scripts is provided, all scripts will be queried. If no list of languages is provided, all
-- languages will be queried. If no list of features is provided, all features will be queried.
ot_layout_collect_lookups :: MonadIO m => Face -> Tag -> Maybe [Tag] -> Maybe [Tag] -> Maybe [Tag] -> Set -> m ()
ot_layout_collect_lookups face table_tag scripts languages features lookup_indices = liftIO $
  [C.block|void { hb_ot_layout_collect_lookups( $face:face, $(hb_tag_t table_tag), $maybe-tags:scripts, $maybe-tags:languages, $maybe-tags:features, $set:lookup_indices); }|]

-- | Fetches a list of all feature indexes in the specified face's GSUB table or GPOS table, underneath the specified scripts,
-- languages, and features. If no list of scripts is provided, all scripts will be queried. If no list of languages is provided,
-- all languages will be queried. If no list of features is provided, all features will be queried.
ot_layout_collect_features :: MonadIO m => Face -> Tag -> Maybe [Tag] -> Maybe [Tag] -> Maybe [Tag] -> Set -> m ()
ot_layout_collect_features face table_tag scripts languages features feature_indices = liftIO $
  [C.block|void { hb_ot_layout_collect_features( $face:face, $(hb_tag_t table_tag), $maybe-tags:scripts, $maybe-tags:languages, $maybe-tags:features, $set:feature_indices); }|]

-- | Fetches a list of the characters defined as having a variant under the specified "Character Variant" ("cvXX") feature tag.
--
-- Note: If the length of the list of codepoints is equal to the supplied char_count then there is a chance that there where
-- more characters defined under the feature tag than were returned. This function can be called with incrementally larger
-- start_offset until the char_count output value is lower than its input value, or the size of the characters array can be increased.
ot_layout_feature_get_characters :: MonadIO m => Face -> Tag -> Int -> Int -> Int -> m (Int, [Codepoint])
ot_layout_feature_get_characters face table_tag (fromIntegral -> feature_index) (fromIntegral -> start_offset) char_count = liftIO $
  allocaArray char_count $ \ pcharacters ->
    with (fromIntegral char_count) $ \pchar_count -> do
      n <- [C.exp|unsigned int { hb_ot_layout_feature_get_characters( $face:face, $(hb_tag_t table_tag), $(unsigned int feature_index), $(unsigned int start_offset), $(unsigned int * pchar_count), $(hb_codepoint_t * pcharacters)) }|]
      actual_char_count <- peek pchar_count
      cs <- peekArray (fromIntegral actual_char_count) pcharacters
      pure (fromIntegral n, cs)


-- | Fetches a list of all lookups enumerated for the specified feature, in the specified face's GSUB table or GPOS table.
-- The list returned will begin at the offset provided.
ot_layout_feature_get_lookups :: MonadIO m => Face -> Tag -> Int -> Int -> Int -> m (Int, [Int])
ot_layout_feature_get_lookups face table_tag (fromIntegral -> feature_index) (fromIntegral -> start_offset) lookup_count = liftIO $
  allocaArray lookup_count $ \plookup_indices ->
    with (fromIntegral lookup_count) $ \plookup_count -> do
      n <- [C.exp|unsigned int { hb_ot_layout_feature_get_lookups( $face:face, $(hb_tag_t table_tag), $(unsigned int feature_index), $(unsigned int start_offset), $(unsigned int * plookup_count), $(unsigned int * plookup_indices)) }|]
      actual_lookup_count <- peek plookup_count
      is <- peekArray (fromIntegral actual_lookup_count) plookup_indices
      pure (fromIntegral n, fromIntegral <$> is)

ot_tag_to_script :: Tag -> Script
ot_tag_to_script tag =[C.pure|hb_script_t { hb_ot_tag_to_script($(hb_tag_t tag)) }|]

ot_tag_to_language :: Tag -> Language
ot_tag_to_language tag = Language [C.pure|hb_language_t { hb_ot_tag_to_language($(hb_tag_t tag)) }|]

ot_tags_from_script_and_language :: Script -> Language -> ([Tag],[Tag])
ot_tags_from_script_and_language script language = unsafeLocalState $
  allocaArray 256 $ \pscripts ->
    withArray [128,128] $ \pscript_count -> do
      let planguages = advancePtr pscripts 128
          planguage_count = advancePtr pscript_count 1
      [C.block|void { hb_ot_tags_from_script_and_language( $(hb_script_t script), $language:language, $(unsigned int * pscript_count), $(hb_tag_t * pscripts), $(unsigned int * planguage_count), $(hb_tag_t * planguages)); }|]
      nscripts <- fromIntegral <$> peek pscript_count
      nlanguages <- fromIntegral <$> peek planguage_count
      (,) <$> peekArray nscripts pscripts <*> peekArray nlanguages planguages

ot_tags_to_script_and_language :: Tag -> Tag -> (Script,Language)
ot_tags_to_script_and_language script_tag language_tag = unsafeLocalState $
  alloca $ \pscript -> alloca $ \ planguage -> do
    [C.block|void { hb_ot_tags_to_script_and_language( $(hb_tag_t script_tag),$(hb_tag_t language_tag),$(hb_script_t * pscript),$(hb_language_t * planguage)); }|]
    (,) <$> peek pscript <*> (Language <$> peek planguage)

ot_name_list_names :: MonadIO m => Face -> m [OpenTypeNameEntry]
ot_name_list_names face = liftIO $
  alloca $ \plen -> do
    entries <- [C.exp|const hb_ot_name_entry_t * { hb_ot_name_list_names ($face:face,$(unsigned int * plen)) }|]
    len <- peek plen
    peekArray (fromIntegral len) entries -- do not free

ot_name_get_ :: Face -> OpenTypeName -> Language -> Int -> IO (Either Int String)
ot_name_get_ face name language buflen = do
  with (fromIntegral buflen) $ \pbuflen -> do
    allocaBytes buflen $ \buf -> do
      full_len <- fromIntegral <$> [C.exp|unsigned int { hb_ot_name_get_utf32($face:face,$(hb_ot_name_id_t name),$language:language,$(unsigned int * pbuflen),$(uint32_t * buf))}|]
      if full_len > buflen
      then pure $ Left full_len
      else Right <$> do
        actual_len <- peek pbuflen
        peekArray (fromIntegral actual_len) (castPtr buf)

ot_name_get :: MonadIO m => Face -> OpenTypeName -> Language -> m (Maybe String)
ot_name_get face name language = liftIO $
  ot_name_get_ face name language 1024 >>= \case
    Left n -> ot_name_get_ face name language n >>= \case -- slow path
      Left n' -> fail $ "ot_name_get: multiple fetches failed: actual length: " ++ show n'
      Right s -> pure $ Just s
    Right s -> pure $ Just s

ot_shape_glyphs_closure :: MonadIO m => Font -> Buffer -> [Feature] -> Set -> m ()
ot_shape_glyphs_closure font buffer features glyphs = liftIO $
  withArrayLen features $ \ (fromIntegral -> num_features) pfeatures ->
    [C.block|void { hb_ot_shape_glyphs_closure( $font:font, $buffer:buffer, $(const hb_feature_t * pfeatures), $(unsigned int num_features), $set:glyphs); }|]