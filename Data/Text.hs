{-# LANGUAGE BangPatterns, CPP, MagicHash, Rank2Types, UnboxedTuples #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
#if __GLASGOW_HASKELL__ >= 702
{-# LANGUAGE Trustworthy #-}
#endif
#if __GLASGOW_HASKELL__ >= 708
{-# LANGUAGE TypeFamilies #-}
#endif

#ifdef VECFUNCTIONS
#if defined(__GLASGOW_HASKELL__) && !defined(__HADDOCK__)
#include "MachDeps.h"
#endif
#endif

-- |
-- Module      : Data.Text
-- Copyright   : (c) 2009, 2010, 2011, 2012 Bryan O'Sullivan,
--               (c) 2009 Duncan Coutts,
--               (c) 2008, 2009 Tom Harper
--
-- License     : BSD-style
-- Maintainer  : bos@serpentine.com
-- Portability : GHC
--
-- A time and space-efficient implementation of Unicode text.
-- Suitable for performance critical use, both in terms of large data
-- quantities and high speed.
--
-- /Note/: Read below the synopsis for important notes on the use of
-- this module.
--
-- This module is intended to be imported @qualified@, to avoid name
-- clashes with "Prelude" functions, e.g.
--
-- > import qualified Data.Text as T
--
-- To use an extended and very rich family of functions for working
-- with Unicode text (including normalization, regular expressions,
-- non-standard encodings, text breaking, and locales), see the
-- <http://hackage.haskell.org/package/text-icu text-icu package >.
--

module Data.Text
    (
    -- * Strict vs lazy types
    -- $strict

    -- * Acceptable data
    -- $replacement

    -- * Definition of character
    -- $character_definition

    -- * Fusion
    -- $fusion

    -- * Types
      Text

    -- * Creation and elimination
    , pack
    , unpack
    , singleton
    , empty

    -- * Basic interface
    , cons
    , snoc
    , append
    , uncons
    , unsnoc
    , head
    , last
    , tail
    , init
    , null
    , length
    , compareLength

    -- * Transformations
    , map
    , intercalate
    , intersperse
    , transpose
    , reverse
    , replace

    -- ** Case conversion
    -- $case
    , toCaseFold
    , toLower
    , toUpper
    , toTitle

    -- ** Justification
    , justifyLeft
    , justifyRight
    , center

    -- * Folds
    , foldl
    , foldl'
    , foldl1
    , foldl1'
    , foldr
    , foldr1

    -- ** Special folds
    , concat
    , concatMap
    , any
    , all
    , maximum
    , minimum

    -- * Construction

    -- ** Scans
    , scanl
    , scanl1
    , scanr
    , scanr1

    -- ** Accumulating maps
    , mapAccumL
    , mapAccumR

    -- ** Generation and unfolding
    , replicate
    , unfoldr
    , unfoldrN

    -- * Substrings

    -- ** Breaking strings
    , take
    , takeEnd
    , drop
    , dropEnd
    , takeWhile
    , takeWhileEnd
    , dropWhile
    , dropWhileEnd
    , dropAround
    , strip
    , stripStart
    , stripEnd
    , splitAt
    , breakOn
    , breakOnEnd
    , break
    , span
    , group
    , groupBy
    , inits
    , tails

    -- ** Breaking into many substrings
    -- $split
    , splitOn
    , split
    , chunksOf

    -- ** Breaking into lines and words
    , lines
    --, lines'
    , words
    , unlines
    , unwords

    -- * Predicates
    , isPrefixOf
    , isSuffixOf
    , isInfixOf

    -- ** View patterns
    , stripPrefix
    , stripSuffix
    , commonPrefixes

    -- * Searching
    , filter
    , breakOnAll
    , find
    , partition

    -- , findSubstring

    -- * Indexing
    -- $index
    , index
    , findIndex
    , count

    -- * Zipping
    , zip
    , zipWith

    -- -* Ordered text
    -- , sort

    -- * Low level operations
    , copy
    , unpackCString#
    ) where

import Prelude (Char, Bool(..), Int, Maybe(..), String,
                Eq(..), Ord(..), Ordering(..), (++),
                Read(..),
                (&&), (||), (+), (-), (.), ($), ($!), (>>),
                not, return, otherwise, quot)
#if defined(HAVE_DEEPSEQ)
import Control.DeepSeq (NFData(rnf))
#endif
#if defined(ASSERTS)
import Control.Exception (assert)
#endif
import Data.Char (isSpace)
import Data.Data (Data(gfoldl, toConstr, gunfold, dataTypeOf), constrIndex,
                  Constr, mkConstr, DataType, mkDataType, Fixity(Prefix))
import Control.Monad (foldM)
import Control.Monad.ST (ST)
import qualified Data.Text.Array as A
import qualified Data.List as L
import Data.Binary (Binary(get, put))
import Data.Monoid (Monoid(..))
#if MIN_VERSION_base(4,9,0)
import Data.Semigroup (Semigroup(..))
#endif
import Data.String (IsString(..))
import qualified Data.Text.Internal.Fusion as S
import qualified Data.Text.Internal.Fusion.Common as S
import Data.Text.Encoding (decodeUtf8', encodeUtf8)
import Data.Text.Internal.Fusion (stream, reverseStream, unstream)
import Data.Text.Internal.Private (span_)
import Data.Text.Internal (Text(..), empty, firstf, mul, safe, text)
import Data.Text.Show (singleton, unpack, unpackCString#)
import qualified Prelude as P
import Data.Text.Unsafe (Iter(..), iter, iter_, lengthWord8, reverseIter,
                         reverseIter_, unsafeHead, unsafeTail, takeWord8)
import qualified Data.Text.Internal.Functions as F
import qualified Data.Text.Internal.Encoding.Utf8 as U8
import Data.Text.Internal.Search (indices)
#if defined(__HADDOCK__)
import Data.ByteString (ByteString)
import qualified Data.Text.Lazy as L
import Data.Int (Int64)
#endif
import GHC.Base (eqInt, neInt, gtInt, geInt, ltInt, leInt)
#if __GLASGOW_HASKELL__ >= 708
import qualified GHC.Exts as Exts
#endif
#if MIN_VERSION_base(4,7,0)
import Text.Printf (PrintfArg, formatArg, formatString)
#endif

#ifdef VECFUNCTIONS
import GHC.Prim
#endif

-- $character_definition
--
-- This package uses the term /character/ to denote Unicode /code points/.
--
-- Note that this is not the same thing as a grapheme (e.g. a
-- composition of code points that form one visual symbol). For
-- instance, consider the grapheme \"&#x00e4;\". This symbol has two
-- Unicode representations: a single code-point representation
-- @U+00E4@ (the @LATIN SMALL LETTER A WITH DIAERESIS@ code point),
-- and a two code point representation @U+0061@ (the \"@A@\" code
-- point) and @U+0308@ (the @COMBINING DIAERESIS@ code point).

-- $strict
--
-- This package provides both strict and lazy 'Text' types.  The
-- strict type is provided by the "Data.Text" module, while the lazy
-- type is provided by the "Data.Text.Lazy" module. Internally, the
-- lazy @Text@ type consists of a list of strict chunks.
--
-- The strict 'Text' type requires that an entire string fit into
-- memory at once.  The lazy 'Data.Text.Lazy.Text' type is capable of
-- streaming strings that are larger than memory using a small memory
-- footprint.  In many cases, the overhead of chunked streaming makes
-- the lazy 'Data.Text.Lazy.Text' type slower than its strict
-- counterpart, but this is not always the case.  Sometimes, the time
-- complexity of a function in one module may be different from the
-- other, due to their differing internal structures.
--
-- Each module provides an almost identical API, with the main
-- difference being that the strict module uses 'Int' values for
-- lengths and counts, while the lazy module uses 'Data.Int.Int64'
-- lengths.

-- $replacement
--
-- A 'Text' value is a sequence of Unicode scalar values, as defined
-- in
-- <http://www.unicode.org/versions/Unicode5.2.0/ch03.pdf#page=35 §3.9, definition D76 of the Unicode 5.2 standard >.
-- As such, a 'Text' cannot contain values in the range U+D800 to
-- U+DFFF inclusive. Haskell implementations admit all Unicode code
-- points
-- (<http://www.unicode.org/versions/Unicode5.2.0/ch03.pdf#page=13 §3.4, definition D10 >)
-- as 'Char' values, including code points from this invalid range.
-- This means that there are some 'Char' values that are not valid
-- Unicode scalar values, and the functions in this module must handle
-- those cases.
--
-- Within this module, many functions construct a 'Text' from one or
-- more 'Char' values. Those functions will substitute 'Char' values
-- that are not valid Unicode scalar values with the replacement
-- character \"&#xfffd;\" (U+FFFD).  Functions that perform this
-- inspection and replacement are documented with the phrase
-- \"Performs replacement on invalid scalar values\".
--
-- (One reason for this policy of replacement is that internally, a
-- 'Text' value is represented as packed UTF-8 data. Values in the
-- range U+D800 through U+DFFF are used by UTF-16 to denote surrogate
-- code points, and so cannot be represented. The functions replace
-- invalid scalar values, instead of dropping them, as a security
-- measure. For details, see
-- <http://unicode.org/reports/tr36/#Deletion_of_Noncharacters Unicode Technical Report 36, §3.5 >.)

-- $fusion
--
-- Most of the functions in this module are subject to /fusion/,
-- meaning that a pipeline of such functions will usually allocate at
-- most one 'Text' value.
--
-- As an example, consider the following pipeline:
--
-- > import Data.Text as T
-- > import Data.Text.Encoding as E
-- > import Data.ByteString (ByteString)
-- >
-- > countChars :: ByteString -> Int
-- > countChars = T.length . T.toUpper . E.decodeUtf8
--
-- From the type signatures involved, this looks like it should
-- allocate one 'Data.ByteString.ByteString' value, and two 'Text'
-- values. However, when a module is compiled with optimisation
-- enabled under GHC, the two intermediate 'Text' values will be
-- optimised away, and the function will be compiled down to a single
-- loop over the source 'Data.ByteString.ByteString'.
--
-- Functions that can be fused by the compiler are documented with the
-- phrase \"Subject to fusion\".

instance Eq Text where
    Text arrA offA lenA == Text arrB offB lenB
        | lenA == lenB = A.equal arrA offA arrB offB lenA
        | otherwise    = False
    {-# INLINE (==) #-}

instance Ord Text where
    compare = compareText

instance Read Text where
    readsPrec p str = [(pack x,y) | (x,y) <- readsPrec p str]

#if MIN_VERSION_base(4,9,0)
-- | Non-orphan 'Semigroup' instance only defined for
-- @base-4.9.0.0@ and later; orphan instances for older GHCs are
-- provided by
-- the [semigroups](http://hackage.haskell.org/package/semigroups)
-- package
--
-- @since 1.2.2.0
instance Semigroup Text where
    (<>) = append
#endif

instance Monoid Text where
    mempty  = empty
#if MIN_VERSION_base(4,9,0)
    mappend = (<>) -- future-proof definition
#else
    mappend = append
#endif
    mconcat = concat

instance IsString Text where
    fromString = pack

#if __GLASGOW_HASKELL__ >= 708
-- | @since 1.2.0.0
instance Exts.IsList Text where
    type Item Text = Char
    fromList       = pack
    toList         = unpack
#endif

#if defined(HAVE_DEEPSEQ)
instance NFData Text where rnf !_ = ()
#endif

-- | @since 1.2.1.0
instance Binary Text where
    put t = put (encodeUtf8 t)
    get   = do
      bs <- get
      case decodeUtf8' bs of
        P.Left exn -> P.fail (P.show exn)
        P.Right a -> P.return a

-- | This instance preserves data abstraction at the cost of inefficiency.
-- We omit reflection services for the sake of data abstraction.
--
-- This instance was created by copying the updated behavior of
-- @"Data.Set".@'Data.Set.Set' and @"Data.Map".@'Data.Map.Map'. If you
-- feel a mistake has been made, please feel free to submit
-- improvements.
--
-- The original discussion is archived here:
-- <http://groups.google.com/group/haskell-cafe/browse_thread/thread/b5bbb1b28a7e525d/0639d46852575b93 could we get a Data instance for Data.Text.Text? >
--
-- The followup discussion that changed the behavior of 'Data.Set.Set'
-- and 'Data.Map.Map' is archived here:
-- <http://markmail.org/message/trovdc6zkphyi3cr#query:+page:1+mid:a46der3iacwjcf6n+state:results Proposal: Allow gunfold for Data.Map, ... >

instance Data Text where
  gfoldl f z txt = z pack `f` (unpack txt)
  toConstr _ = packConstr
  gunfold k z c = case constrIndex c of
    1 -> k (z pack)
    _ -> P.error "gunfold"
  dataTypeOf _ = textDataType

#if MIN_VERSION_base(4,7,0)
-- | Only defined for @base-4.7.0.0@ and later
--
-- @since 1.2.2.0
instance PrintfArg Text where
  formatArg txt = formatString $ unpack txt
#endif

packConstr :: Constr
packConstr = mkConstr textDataType "pack" [] Prefix

textDataType :: DataType
textDataType = mkDataType "Data.Text.Text" [packConstr]

-- | /O(n)/ Compare two 'Text' values lexicographically.
compareText :: Text -> Text -> Ordering
compareText (Text arrA offA lenA) (Text arrB offB lenB)
    | lenA == 0 || lenB == 0 = compare lenA lenB
    | otherwise =
        A.cmp arrA offA arrB offB (min lenA lenB) `mappend` compare lenA lenB

-- -----------------------------------------------------------------------------
-- * Conversion to/from 'Text'

-- | /O(n)/ Convert a 'String' into a 'Text'.  Subject to
-- fusion.  Performs replacement on invalid scalar values.
pack :: String -> Text
pack = unstream . S.map safe . S.streamList
{-# INLINE [1] pack #-}

-- -----------------------------------------------------------------------------
-- * Basic functions

-- | /O(n)/ Adds a character to the front of a 'Text'.  This function
-- is more costly than its 'List' counterpart because it requires
-- copying a new array.  Subject to fusion.  Performs replacement on
-- invalid scalar values.
cons :: Char -> Text -> Text
cons c t = unstream (S.cons (safe c) (stream t))
{-# INLINE cons #-}

infixr 5 `cons`

-- | /O(n)/ Adds a character to the end of a 'Text'.  This copies the
-- entire array in the process, unless fused.  Subject to fusion.
-- Performs replacement on invalid scalar values.
snoc :: Text -> Char -> Text
snoc t c = unstream (S.snoc (stream t) (safe c))
{-# INLINE snoc #-}

-- | /O(n)/ Appends one 'Text' to the other by copying both of them
-- into a new 'Text'.  Subject to fusion.
append :: Text -> Text -> Text
append a@(Text arr1 off1 len1) b@(Text arr2 off2 len2)
    | len1 == 0 = b
    | len2 == 0 = a
    | len > 0   = Text (A.run x) 0 len
    | otherwise = overflowError "append"
    where
      len = len1+len2
      x :: ST s (A.MArray s)
      x = do
        arr <- A.new len
        A.copyI arr 0 arr1 off1 len1
        A.copyI arr len1 arr2 off2 len
        return arr
{-# NOINLINE append #-}

{-# RULES
"TEXT append -> fused" [~1] forall t1 t2.
    append t1 t2 = unstream (S.append (stream t1) (stream t2))
"TEXT append -> unfused" [1] forall t1 t2.
    unstream (S.append (stream t1) (stream t2)) = append t1 t2
 #-}

-- | /O(1)/ Returns the first character of a 'Text', which must be
-- non-empty.  Subject to fusion.
head :: Text -> Char
head t = S.head (stream t)
{-# INLINE head #-}

-- | /O(1)/ Returns the first character and rest of a 'Text', or
-- 'Nothing' if empty. Subject to fusion.
uncons :: Text -> Maybe (Char, Text)
uncons t@(Text arr off len)
    | len <= 0  = Nothing
    | otherwise = Just $ let !(Iter c d) = iter t 0
                         in (c, text arr (off+d) (len-d))
{-# INLINE [1] uncons #-}

-- | Lifted from Control.Arrow and specialized.
second :: (b -> c) -> (a,b) -> (a,c)
second f (a, b) = (a, f b)

-- | /O(1)/ Returns the last character of a 'Text', which must be
-- non-empty.  Subject to fusion.
last :: Text -> Char
last (Text arr off len)
    | len <= 0                 = emptyError "last"
    | otherwise = U8.reverseDecodeCharIndex (\c _ -> c) idx (off + len - 1)
  where
    idx = A.unsafeIndex arr
{-# INLINE [1] last #-}

{-# RULES
"TEXT last -> fused" [~1] forall t.
    last t = S.last (stream t)
"TEXT last -> unfused" [1] forall t.
    S.last (stream t) = last t
  #-}

-- | /O(1)/ Returns all characters after the head of a 'Text', which
-- must be non-empty.  Subject to fusion.
tail :: Text -> Text
tail t@(Text arr off len)
    | len <= 0  = emptyError "tail"
    | otherwise = text arr (off+d) (len-d)
    where d = iter_ t 0
{-# INLINE [1] tail #-}

{-# RULES
"TEXT tail -> fused" [~1] forall t.
    tail t = unstream (S.tail (stream t))
"TEXT tail -> unfused" [1] forall t.
    unstream (S.tail (stream t)) = tail t
 #-}

-- | /O(1)/ Returns all but the last character of a 'Text', which must
-- be non-empty.  Subject to fusion.
init :: Text -> Text
init t@(Text arr off len)
    | len <= 0  = emptyError "init"
    | otherwise = U8.reverseDecodeCharIndex
        (\_ s -> takeWord8 (len - s) t) idx (off + len - 1)
  where
    idx = A.unsafeIndex arr
{-# INLINE [1] init #-}

{-# RULES
"TEXT init -> fused" [~1] forall t.
    init t = unstream (S.init (stream t))
"TEXT init -> unfused" [1] forall t.
    unstream (S.init (stream t)) = init t
 #-}

-- | /O(1)/ Returns all but the last character and the last character of a
-- 'Text', or 'Nothing' if empty.
--
-- @since 1.2.3.0
unsnoc :: Text -> Maybe (Text, Char)
unsnoc t@(Text _ _ len)
    | len <= 0                 = Nothing
    | otherwise                = Just (init t, last t) -- TODO
{-# INLINE [1] unsnoc #-}

-- | /O(1)/ Tests whether a 'Text' is empty or not.  Subject to
-- fusion.
null :: Text -> Bool
null (Text _arr _off len) =
#if defined(ASSERTS)
    assert (len >= 0) $
#endif
    len <= 0
{-# INLINE [1] null #-}

{-# RULES
"TEXT null -> fused" [~1] forall t.
    null t = S.null (stream t)
"TEXT null -> unfused" [1] forall t.
    S.null (stream t) = null t
 #-}

-- | /O(1)/ Tests whether a 'Text' contains exactly one character.
-- Subject to fusion.
isSingleton :: Text -> Bool
isSingleton = S.isSingleton . stream
{-# INLINE isSingleton #-}


#ifdef VECFUNCTIONS
#if WORD_SIZE_IN_BITS == 64
#define READWORD   indexWord64Array#
#define ALIGN_MASK 0x07#
#define WORDBYTES  8#
#define WORDBYTESW (int2Word# 8#)
#define SUMSHIFT   56#
-- SUMSHIFT = (sizeof(Word#)-1) * 8
#else
#define READWORD   indexWord32Array#
#define ALIGN_MASK 0x03#
#define WORDBYTES  4#
#define WORDBYTESW (int2Word# 4#)
#define SUMSHIFT   24#
#endif

-- Returns 1 if the given byte is a continuation byte (0b10xxxxxx), assumes
-- value is between 0 and 255
isContByte# :: Word# -> Word#
{-# INLINE isContByte# #-}
isContByte# b# =
    and#
        (uncheckedShiftRL#       b#  7#)
        (uncheckedShiftRL# (not# b#) 6#)

-- Counts the number of continuation bytes (0x10xxxxxx) contained in a given
-- `Word#`.
countContBytes# :: Word# -> Word#
{-# INLINE countContBytes# #-}
countContBytes# n# = let
    ones#     = quotWord# (int2Word# -1#) 0xFF##
    --          0x80808080...
    highOnes# = timesWord# ones# 0x80##
    u# = and#
        (uncheckedShiftRL# (and# n# highOnes#) 7#)
        (uncheckedShiftRL# (not# n#)           6#)
    in uncheckedShiftRL# (timesWord# u# ones#) SUMSHIFT

#endif


-- | /O(n)/ Returns the number of characters in a 'Text'.
-- Subject to fusion.

#ifndef VECFUNCTIONS

length :: Text -> Int
length t = S.length (stream t)
{-# INLINE [0] length #-}
-- length needs to be phased after the compareN/length rules otherwise
-- it may inline before the rules have an opportunity to fire.

#else

-- | Counts the number of codepoints present in a given 'Text'. It uses a fast
-- algorithm which avoids the need to decode every character.

-- It uses the algorithm found at
-- http://www.daemonology.net/blog/2008-06-05-faster-utf8-strlen.html but should
-- be slightly faster as there is no need to check for null bytes, so data
-- dependent branches are eliminated.
length :: Text -> Int
length (Text arr (Exts.I# off0#) (Exts.I# len0#)) =
    initFastLength off0# 0## where
    ba = A.aBA arr
    end# = off0# +# len0#
    endVec# = quotInt# end# WORDBYTES
    -- loop until we're at a multiple of WORDBYTES bytes. Works by counting how
    -- many non-start-of-codepoint bytes there are (bytes matching the pattern
    -- 0b10xxxxxx) and subtracting that from the number of bytes in the Text -
    -- all other bytes must have been codepoint starting bytes if it is valid
    -- utf-8.
    --
    -- Parameters are the offset into the buffer and the number of continuation
    -- bytes seen so far.
    initFastLength :: Int# -> Word# -> Int
    initFastLength off# nonStart#
        -- For short, unaligned strings, exit after counting a byte at a time
        | Exts.isTrue# (off# >=# end#)  = Exts.I# (len0# -# word2Int# nonStart#)
        -- search until we've found a Word aligned boundary
        | Exts.isTrue# (andI# off# ALIGN_MASK ==# 0#) =
            vecFastLength (quotInt# off# WORDBYTES) nonStart#
        | otherwise = initFastLength (off# +# 1#)
                        (plusWord# nonStart# (isContByte# (indexWord8Array# ba off#)))

    -- process bytes WORDBYTES at a time, offset is in words, not bytes. This
    -- counts the number of bytes in the word which match the pattern
    -- 0b10xxxxxx, i.e. continuation bytes.
    --
    -- TODO: unroll this to process several Words at a time.
    vecFastLength :: Int# -> Word# -> Int
    vecFastLength offWord# nonStart#
        | Exts.isTrue# (offWord# >=# endVec#) =
            endFastLength (offWord# *# WORDBYTES) nonStart#
        | otherwise = vecFastLength
                (offWord# +# 1#)
                (plusWord# nonStart# (countContBytes# (READWORD ba offWord#)))

    -- clean up remaining data at end of buffer
    endFastLength :: Int# -> Word# -> Int
    endFastLength off# nonStart#
        | Exts.isTrue# (off# >=# end#) = Exts.I# (len0# -# word2Int# nonStart#)
        | otherwise = endFastLength (off# +# 1#)
                        (plusWord# nonStart# (isContByte# (indexWord8Array# ba off#)))

-- | Returns the length of the `Text` up to the given codepoint, or -1 if n is
-- greater than the number of codepoints in the `Text`.
nthCodepoint :: Int -> Text -> Int
nthCodepoint (Exts.I# n0#) (Text arr (Exts.I# off0#) (Exts.I# len0#))
    -- if n > len there are definitely less than n characters
    | Exts.isTrue# (n0# >=# len0#) = -1
    | Exts.isTrue# (n0# <# 0#)     = 0
    | otherwise = initFastNth off0# (int2Word# n0#) where
    ba = A.aBA arr
    end# = off0# +# len0#
    endVec# = quotInt# end# WORDBYTES

    initFastNth :: Int# -> Word# -> Int
    initFastNth off# n#
        | Exts.isTrue# (off# >=# end#)    = -1
        -- If n less than bytes/word, clean up in the epilogue loop
        | Exts.isTrue# (n# `leWord#` WORDBYTESW) = endFastNth off# n#
        -- If word aligned, process in the fast loop
        | Exts.isTrue# (andI# off# ALIGN_MASK ==# 0#) =
            -- endFastNth off# n#
            vecFastNth (quotInt# off# WORDBYTES) n#
        | otherwise = case indexWord8Array# ba off# of
            -- isContByte b     = 1|0
            -- isContByte b - 1 = 0|-1
            -- therefore, we only subtract 1 from n if it is not a continuation byte
            b# -> initFastNth (off# +# 1#) (plusWord# n# (minusWord# (isContByte# b#) 1##))
    
    -- Count down n one word at a time. Offset is in Word#'s not bytes
    vecFastNth :: Int# -> Word# -> Int
    vecFastNth offWord# n#
        -- Check for end of array, or if there are less than #bytes/word left
        -- left to find and let endFastNth take care of any cleanup.
        | Exts.isTrue# ((offWord# >=# endVec#) `orI#` leWord# n# WORDBYTESW) =
            endFastNth (offWord# *# WORDBYTES) n#
        | otherwise = vecFastNth
                (offWord# +# 1#)
                -- Subtract #bytes/word, add the number of non codepoint start
                -- chars
                (plusWord#
                    (minusWord# n# WORDBYTESW)
                    (countContBytes# (READWORD ba offWord#)))

    endFastNth :: Int# -> Word# -> Int
    endFastNth off# n#
        -- overrun
        | Exts.isTrue# (off# >=# end#)    = -1
        -- still more characters to find
        | Exts.isTrue# (n# `gtWord#` 0##) = let
            b# = indexWord8Array# ba off#
            -- isContByte b     = 1|0
            -- isContByte b - 1 = 0|-1
            -- therefore, we only subtract 1 from n if it is not a continuation byte
            in endFastNth (off# +# 1#) (plusWord# n# (minusWord# (isContByte# b#) 1##))
        -- n == 0
        | otherwise = cleanEnd off#
    
    -- Cleans up the final character, finds the offset to the next
    -- non-continuation byte
    cleanEnd :: Int# -> Int
    cleanEnd off#
        -- overrun
        | Exts.isTrue# (off# >=# end#)    = -1
        -- if it's a continuation byte, search again
        | Exts.isTrue# (word2Int# (isContByte# (indexWord8Array# ba off#)))
            = cleanEnd (off# +# 1#)
        -- If this is not a contiunuation byte, the previous byte is the last one
        | otherwise                       = Exts.I# off#


-- | Returns the offset of the byte which starts the 'n'th codepoint from the
-- _end_ of the 'Text', or '-1' if there are more than 'n' codepoints prersent.
-- If 'n' is negative, 0 is returned (it is treated the same as if zero was passed).
-- Used for fast take/dropEnd.
nthCodepointEnd :: Int -> Text -> Int
nthCodepointEnd (Exts.I# n0#) (Text arr (Exts.I# off0#) (Exts.I# len0#))
    -- if n > len there are definitely less than n characters
    | Exts.isTrue# (n0# >=# len0#) = -1
    | Exts.isTrue# (n0# <# 0#)     = 0
    | otherwise = initFastNthEnd (off0# +# len0#) (int2Word# n0#) where
    ba = A.aBA arr
    start# = off0#
    startVec# = quotInt# start# WORDBYTES

    initFastNthEnd :: Int# -> Word# -> Int
    initFastNthEnd off# n#
        | Exts.isTrue# (off# < start#)    = -1
        -- If n less than bytes/word, clean up in the epilogue loop
        | Exts.isTrue# (n# `leWord#` WORDBYTESW) = endFastNthEnd off# n#
        -- If word aligned, process in the fast loop
        | otherwise = case indexWord8Array# ba off# of
            b# 
                -- If the current byte is at a WORD boundary, count it and start
                -- vectorised counting from _previous_ WORD.
                | Exts.isTrue# (andI# off# ALIGN_MASK ==# 0#)
                    -> vecFastNthEnd 
                        (quotInt# off# WORDBYTES -# 1) 
                        (plusWord# n# (minusWord# (isContByte# b#) 1##))
                -- keep looking for WORD boundard
                | otherwise -> 
                    initFastNthEnd 
                        (off# -# 1#)
                        (plusWord# n# (minusWord# (isContByte# b#) 1##))
            -- isContByte b     = 1|0
            -- isContByte b - 1 = 0|-1
            -- therefore, we only subtract 1 from n if it is a start byte (not continuation)

    -- Count down n one word at a time. Offset is in Word#'s not bytes
    vecFastNthEnd :: Int# -> Word# -> Int
    vecFastNthEnd offWord# n#
        -- Check for end of array, or if there are less than #bytes/word left
        -- left to find and let endFastNthEnd take care of any cleanup.
        | Exts.isTrue# ((offWord# <=# startVec#) `orI#` leWord# n# WORDBYTESW) =
            endFastNthEnd (offWord# *# WORDBYTES) n#
        | otherwise = vecFastNthEnd
                (offWord# -# 1#)
                -- Subtract #bytes/word, add the number of non codepoint start
                -- chars
                (plusWord#
                    (minusWord# n# WORDBYTESW)
                    (countContBytes# (READWORD ba offWord#)))

    endFastNthEnd :: Int# -> Word# -> Int
    endFastNthEnd off# n#
        -- overrun
        | Exts.isTrue# (off# <# start#)    = -1
        -- still more characters to find
        | Exts.isTrue# (n# `gtWord#` 0##) = let
            b# = indexWord8Array# ba off#
            -- isContByte b     = 1|0
            -- isContByte b - 1 = 0|-1
            -- therefore, we only subtract 1 from n if it is not a continuation byte
            in endFastNthEnd (off# -# 1#) (plusWord# n# (minusWord# (isContByte# b#) 1##))
        -- n == 0
        | otherwise = cleanEnd off#
    
    -- Cleans up the final character, finds the offset to the next
    -- non-continuation byte
    cleanEnd :: Int# -> Int
    cleanEnd off#
        -- overrun
        | Exts.isTrue# (off# <# start#)    = -1
        -- if it's a continuation byte, search again
        | Exts.isTrue# (word2Int# (isContByte# (indexWord8Array# ba off#)))
            = cleanEnd (off# -# 1#)
        -- If this is not a contiunuation byte, the previous byte is the last one
        | otherwise                       = Exts.I# off#


#endif

-- | /O(n)/ Compare the count of characters in a 'Text' to a number.
-- Subject to fusion.
--
-- This function gives the same answer as comparing against the result
-- of 'length', but can short circuit if the count of characters is
-- greater than the number, and hence be more efficient.
compareLength :: Text -> Int -> Ordering
compareLength t n = S.compareLengthI (stream t) n
{-# INLINE [1] compareLength #-}

{-# RULES
"TEXT compareN/length -> compareLength" [~1] forall t n.
    compare (length t) n = compareLength t n
  #-}

{-# RULES
"TEXT ==N/length -> compareLength/==EQ" [~1] forall t n.
    eqInt (length t) n = compareLength t n == EQ
  #-}

{-# RULES
"TEXT /=N/length -> compareLength//=EQ" [~1] forall t n.
    neInt (length t) n = compareLength t n /= EQ
  #-}

{-# RULES
"TEXT <N/length -> compareLength/==LT" [~1] forall t n.
    ltInt (length t) n = compareLength t n == LT
  #-}

{-# RULES
"TEXT <=N/length -> compareLength//=GT" [~1] forall t n.
    leInt (length t) n = compareLength t n /= GT
  #-}

{-# RULES
"TEXT >N/length -> compareLength/==GT" [~1] forall t n.
    gtInt (length t) n = compareLength t n == GT
  #-}

{-# RULES
"TEXT >=N/length -> compareLength//=LT" [~1] forall t n.
    geInt (length t) n = compareLength t n /= LT
  #-}

-- -----------------------------------------------------------------------------
-- * Transformations
-- | /O(n)/ 'map' @f@ @t@ is the 'Text' obtained by applying @f@ to
-- each element of @t@.
--
-- Example:
--
-- >>> let message = pack "I am not angry. Not at all."
-- >>> T.map (\c -> if c == '.' then '!' else c) message
-- "I am not angry! Not at all!"
--
-- Subject to fusion.  Performs replacement on invalid scalar values.
map :: (Char -> Char) -> Text -> Text
map f t = unstream (S.map (safe . f) (stream t))
{-# INLINE [1] map #-}

-- | /O(n)/ The 'intercalate' function takes a 'Text' and a list of
-- 'Text's and concatenates the list after interspersing the first
-- argument between each element of the list.
--
-- Example:
--
-- >>> T.intercalate "NI!" ["We", "seek", "the", "Holy", "Grail"]
-- "WeNI!seekNI!theNI!HolyNI!Grail"
intercalate :: Text -> [Text] -> Text
intercalate t = concat . (F.intersperse t)
{-# INLINE intercalate #-}

-- | /O(n)/ The 'intersperse' function takes a character and places it
-- between the characters of a 'Text'.
--
-- Example:
--
-- >>> T.intersperse '.' "SHIELD"
-- "S.H.I.E.L.D"
--
-- Subject to fusion.  Performs replacement on invalid scalar values.
intersperse     :: Char -> Text -> Text
intersperse c t = unstream (S.intersperse (safe c) (stream t))
{-# INLINE intersperse #-}

-- | /O(n)/ Reverse the characters of a string.
--
-- Example:
--
-- >>> T.reverse "desrever"
-- "reversed"
--
-- Subject to fusion.
reverse :: Text -> Text
reverse t = S.reverse (stream t)
{-# INLINE reverse #-}

-- | /O(m+n)/ Replace every non-overlapping occurrence of @needle@ in
-- @haystack@ with @replacement@.
--
-- This function behaves as though it was defined as follows:
--
-- @
-- replace needle replacement haystack =
--   'intercalate' replacement ('splitOn' needle haystack)
-- @
--
-- As this suggests, each occurrence is replaced exactly once.  So if
-- @needle@ occurs in @replacement@, that occurrence will /not/ itself
-- be replaced recursively:
--
-- >>> replace "oo" "foo" "oo"
-- "foo"
--
-- In cases where several instances of @needle@ overlap, only the
-- first one will be replaced:
--
-- >>> replace "ofo" "bar" "ofofo"
-- "barfo"
--
-- In (unlikely) bad cases, this function's time complexity degrades
-- towards /O(n*m)/.
replace :: Text
        -- ^ @needle@ to search for.  If this string is empty, an
        -- error will occur.
        -> Text
        -- ^ @replacement@ to replace @needle@ with.
        -> Text
        -- ^ @haystack@ in which to search.
        -> Text
replace needle@(Text _      _      neeLen)
               (Text repArr repOff repLen)
      haystack@(Text hayArr hayOff hayLen)
  | neeLen == 0 = emptyError "replace"
  | L.null ixs  = haystack
  | len > 0     = Text (A.run x) 0 len
  | otherwise   = empty
  where
    ixs = indices needle haystack
    len = hayLen - (neeLen - repLen) `mul` L.length ixs
    x :: ST s (A.MArray s)
    x = do
      marr <- A.new len
      let loop (i:is) o d = do
            let d0 = d + i - o
                d1 = d0 + repLen
            A.copyI marr d  hayArr (hayOff+o) d0
            A.copyI marr d0 repArr repOff d1
            loop is (i + neeLen) d1
          loop []     o d = A.copyI marr d hayArr (hayOff+o) len
      loop ixs 0 0
      return marr

-- ----------------------------------------------------------------------------
-- ** Case conversions (folds)

-- $case
--
-- When case converting 'Text' values, do not use combinators like
-- @map toUpper@ to case convert each character of a string
-- individually, as this gives incorrect results according to the
-- rules of some writing systems.  The whole-string case conversion
-- functions from this module, such as @toUpper@, obey the correct
-- case conversion rules.  As a result, these functions may map one
-- input character to two or three output characters. For examples,
-- see the documentation of each function.
--
-- /Note/: In some languages, case conversion is a locale- and
-- context-dependent operation. The case conversion functions in this
-- module are /not/ locale sensitive. Programs that require locale
-- sensitivity should use appropriate versions of the
-- <http://hackage.haskell.org/package/text-icu-0.6.3.7/docs/Data-Text-ICU.html#g:4 case mapping functions from the text-icu package >.

-- | /O(n)/ Convert a string to folded case.  Subject to fusion.
--
-- This function is mainly useful for performing caseless (also known
-- as case insensitive) string comparisons.
--
-- A string @x@ is a caseless match for a string @y@ if and only if:
--
-- @toCaseFold x == toCaseFold y@
--
-- The result string may be longer than the input string, and may
-- differ from applying 'toLower' to the input string.  For instance,
-- the Armenian small ligature \"&#xfb13;\" (men now, U+FB13) is case
-- folded to the sequence \"&#x574;\" (men, U+0574) followed by
-- \"&#x576;\" (now, U+0576), while the Greek \"&#xb5;\" (micro sign,
-- U+00B5) is case folded to \"&#x3bc;\" (small letter mu, U+03BC)
-- instead of itself.
toCaseFold :: Text -> Text
toCaseFold t = unstream (S.toCaseFold (stream t))
{-# INLINE toCaseFold #-}

-- | /O(n)/ Convert a string to lower case, using simple case
-- conversion.  Subject to fusion.
--
-- The result string may be longer than the input string.  For
-- instance, \"&#x130;\" (Latin capital letter I with dot above,
-- U+0130) maps to the sequence \"i\" (Latin small letter i, U+0069)
-- followed by \" &#x307;\" (combining dot above, U+0307).
toLower :: Text -> Text
toLower t = unstream (S.toLower (stream t))
{-# INLINE toLower #-}

-- | /O(n)/ Convert a string to upper case, using simple case
-- conversion.  Subject to fusion.
--
-- The result string may be longer than the input string.  For
-- instance, the German \"&#xdf;\" (eszett, U+00DF) maps to the
-- two-letter sequence \"SS\".
toUpper :: Text -> Text
toUpper t = unstream (S.toUpper (stream t))
{-# INLINE toUpper #-}

-- | /O(n)/ Convert a string to title case, using simple case
-- conversion. Subject to fusion.
--
-- The first letter of the input is converted to title case, as is
-- every subsequent letter that immediately follows a non-letter.
-- Every letter that immediately follows another letter is converted
-- to lower case.
--
-- The result string may be longer than the input string. For example,
-- the Latin small ligature &#xfb02; (U+FB02) is converted to the
-- sequence Latin capital letter F (U+0046) followed by Latin small
-- letter l (U+006C).
--
-- /Note/: this function does not take language or culture specific
-- rules into account. For instance, in English, different style
-- guides disagree on whether the book name \"The Hill of the Red
-- Fox\" is correctly title cased&#x2014;but this function will
-- capitalize /every/ word.
--
-- @since 1.0.0.0
toTitle :: Text -> Text
toTitle t = unstream (S.toTitle (stream t))
{-# INLINE toTitle #-}

-- | /O(n)/ Left-justify a string to the given length, using the
-- specified fill character on the right. Subject to fusion.
-- Performs replacement on invalid scalar values.
--
-- Examples:
--
-- >>> justifyLeft 7 'x' "foo"
-- "fooxxxx"
--
-- >>> justifyLeft 3 'x' "foobar"
-- "foobar"
justifyLeft :: Int -> Char -> Text -> Text
justifyLeft k c t
    | len >= k  = t
    | otherwise = t `append` replicateChar (k-len) c
  where len = length t
{-# INLINE [1] justifyLeft #-}

{-# RULES
"TEXT justifyLeft -> fused" [~1] forall k c t.
    justifyLeft k c t = unstream (S.justifyLeftI k c (stream t))
"TEXT justifyLeft -> unfused" [1] forall k c t.
    unstream (S.justifyLeftI k c (stream t)) = justifyLeft k c t
  #-}

-- | /O(n)/ Right-justify a string to the given length, using the
-- specified fill character on the left.  Performs replacement on
-- invalid scalar values.
--
-- Examples:
--
-- >>> justifyRight 7 'x' "bar"
-- "xxxxbar"
--
-- >>> justifyRight 3 'x' "foobar"
-- "foobar"
justifyRight :: Int -> Char -> Text -> Text
justifyRight k c t
    | len >= k  = t
    | otherwise = replicateChar (k-len) c `append` t
  where len = length t
{-# INLINE justifyRight #-}

-- | /O(n)/ Center a string to the given length, using the specified
-- fill character on either side.  Performs replacement on invalid
-- scalar values.
--
-- Examples:
--
-- >>> center 8 'x' "HS"
-- "xxxHSxxx"
center :: Int -> Char -> Text -> Text
center k c t
    | len >= k  = t
    | otherwise = replicateChar l c `append` t `append` replicateChar r c
  where len = length t
        d   = k - len
        r   = d `quot` 2
        l   = d - r
{-# INLINE center #-}

-- | /O(n)/ The 'transpose' function transposes the rows and columns
-- of its 'Text' argument.  Note that this function uses 'pack',
-- 'unpack', and the list version of transpose, and is thus not very
-- efficient.
--
-- Examples:
--
-- >>> transpose ["green","orange"]
-- ["go","rr","ea","en","ng","e"]
--
-- >>> transpose ["blue","red"]
-- ["br","le","ud","e"]
transpose :: [Text] -> [Text]
transpose ts = P.map pack (L.transpose (P.map unpack ts))

-- -----------------------------------------------------------------------------
-- * Reducing 'Text's (folds)

-- | /O(n)/ 'foldl', applied to a binary operator, a starting value
-- (typically the left-identity of the operator), and a 'Text',
-- reduces the 'Text' using the binary operator, from left to right.
-- Subject to fusion.
foldl :: (a -> Char -> a) -> a -> Text -> a
foldl f z t = S.foldl f z (stream t)
{-# INLINE foldl #-}

-- | /O(n)/ A strict version of 'foldl'.  Subject to fusion.
foldl' :: (a -> Char -> a) -> a -> Text -> a
foldl' f z t = S.foldl' f z (stream t)
{-# INLINE foldl' #-}

-- | /O(n)/ A variant of 'foldl' that has no starting value argument,
-- and thus must be applied to a non-empty 'Text'.  Subject to fusion.
foldl1 :: (Char -> Char -> Char) -> Text -> Char
foldl1 f t = S.foldl1 f (stream t)
{-# INLINE foldl1 #-}

-- | /O(n)/ A strict version of 'foldl1'.  Subject to fusion.
foldl1' :: (Char -> Char -> Char) -> Text -> Char
foldl1' f t = S.foldl1' f (stream t)
{-# INLINE foldl1' #-}

-- | /O(n)/ 'foldr', applied to a binary operator, a starting value
-- (typically the right-identity of the operator), and a 'Text',
-- reduces the 'Text' using the binary operator, from right to left.
-- Subject to fusion.
foldr :: (Char -> a -> a) -> a -> Text -> a
foldr f z t = S.foldr f z (stream t)
{-# INLINE foldr #-}

-- | /O(n)/ A variant of 'foldr' that has no starting value argument,
-- and thus must be applied to a non-empty 'Text'.  Subject to
-- fusion.
foldr1 :: (Char -> Char -> Char) -> Text -> Char
foldr1 f t = S.foldr1 f (stream t)
{-# INLINE foldr1 #-}

-- -----------------------------------------------------------------------------
-- ** Special folds

-- | /O(n)/ Concatenate a list of 'Text's.
concat :: [Text] -> Text
concat ts = case ts' of
              [] -> empty
              [t] -> t
              _ -> Text (A.run go) 0 len
  where
    ts' = L.filter (not . null) ts
    len = sumP "concat" $ L.map lengthWord8 ts'
    go :: ST s (A.MArray s)
    go = do
      arr <- A.new len
      let step i (Text a o l) =
            let !j = i + l in A.copyI arr i a o j >> return j
      foldM step 0 ts' >> return arr

-- | /O(n)/ Map a function over a 'Text' that results in a 'Text', and
-- concatenate the results.
concatMap :: (Char -> Text) -> Text -> Text
concatMap f = concat . foldr ((:) . f) []
{-# INLINE concatMap #-}

-- | /O(n)/ 'any' @p@ @t@ determines whether any character in the
-- 'Text' @t@ satisfies the predicate @p@. Subject to fusion.
any :: (Char -> Bool) -> Text -> Bool
any p t = S.any p (stream t)
{-# INLINE any #-}

-- | /O(n)/ 'all' @p@ @t@ determines whether all characters in the
-- 'Text' @t@ satisfy the predicate @p@. Subject to fusion.
all :: (Char -> Bool) -> Text -> Bool
all p t = S.all p (stream t)
{-# INLINE all #-}

-- | /O(n)/ 'maximum' returns the maximum value from a 'Text', which
-- must be non-empty. Subject to fusion.
maximum :: Text -> Char
maximum t = S.maximum (stream t)
{-# INLINE maximum #-}

-- | /O(n)/ 'minimum' returns the minimum value from a 'Text', which
-- must be non-empty. Subject to fusion.
minimum :: Text -> Char
minimum t = S.minimum (stream t)
{-# INLINE minimum #-}

-- -----------------------------------------------------------------------------
-- * Building 'Text's

-- | /O(n)/ 'scanl' is similar to 'foldl', but returns a list of
-- successive reduced values from the left. Subject to fusion.
-- Performs replacement on invalid scalar values.
--
-- > scanl f z [x1, x2, ...] == [z, z `f` x1, (z `f` x1) `f` x2, ...]
--
-- Note that
--
-- > last (scanl f z xs) == foldl f z xs.
scanl :: (Char -> Char -> Char) -> Char -> Text -> Text
scanl f z t = unstream (S.scanl g z (stream t))
    where g a b = safe (f a b)
{-# INLINE scanl #-}

-- | /O(n)/ 'scanl1' is a variant of 'scanl' that has no starting
-- value argument.  Subject to fusion.  Performs replacement on
-- invalid scalar values.
--
-- > scanl1 f [x1, x2, ...] == [x1, x1 `f` x2, ...]
scanl1 :: (Char -> Char -> Char) -> Text -> Text
scanl1 f t | null t    = empty
           | otherwise = scanl f (unsafeHead t) (unsafeTail t)
{-# INLINE scanl1 #-}

-- | /O(n)/ 'scanr' is the right-to-left dual of 'scanl'.  Performs
-- replacement on invalid scalar values.
--
-- > scanr f v == reverse . scanl (flip f) v . reverse
scanr :: (Char -> Char -> Char) -> Char -> Text -> Text
scanr f z = S.reverse . S.reverseScanr g z . reverseStream
    where g a b = safe (f a b)
{-# INLINE scanr #-}

-- | /O(n)/ 'scanr1' is a variant of 'scanr' that has no starting
-- value argument.  Subject to fusion.  Performs replacement on
-- invalid scalar values.
scanr1 :: (Char -> Char -> Char) -> Text -> Text
scanr1 f t | null t    = empty
           | otherwise = scanr f (last t) (init t)
{-# INLINE scanr1 #-}

-- | /O(n)/ Like a combination of 'map' and 'foldl''. Applies a
-- function to each element of a 'Text', passing an accumulating
-- parameter from left to right, and returns a final 'Text'.  Performs
-- replacement on invalid scalar values.
mapAccumL :: (a -> Char -> (a,Char)) -> a -> Text -> (a, Text)
mapAccumL f z0 = S.mapAccumL g z0 . stream
    where g a b = second safe (f a b)
{-# INLINE mapAccumL #-}

-- | The 'mapAccumR' function behaves like a combination of 'map' and
-- a strict 'foldr'; it applies a function to each element of a
-- 'Text', passing an accumulating parameter from right to left, and
-- returning a final value of this accumulator together with the new
-- 'Text'.
-- Performs replacement on invalid scalar values.
mapAccumR :: (a -> Char -> (a,Char)) -> a -> Text -> (a, Text)
mapAccumR f z0 = second reverse . S.mapAccumL g z0 . reverseStream
    where g a b = second safe (f a b)
{-# INLINE mapAccumR #-}

-- -----------------------------------------------------------------------------
-- ** Generating and unfolding 'Text's

-- | /O(n*m)/ 'replicate' @n@ @t@ is a 'Text' consisting of the input
-- @t@ repeated @n@ times.
replicate :: Int -> Text -> Text
replicate n t@(Text a o l)
    | n <= 0 || l <= 0       = empty
    | n == 1                 = t
    | isSingleton t          = replicateChar n (unsafeHead t)
    | otherwise              = Text (A.run x) 0 len
  where
    len = l `mul` n
    x :: ST s (A.MArray s)
    x = do
      arr <- A.new len
      let loop !d !i | i >= n    = return arr
                     | otherwise = let m = d + l
                                   in A.copyI arr d a o m >> loop m (i+1)
      loop 0 0
{-# INLINE [1] replicate #-}

{-# RULES
"TEXT replicate/singleton -> replicateChar" [~1] forall n c.
    replicate n (singleton c) = replicateChar n c
  #-}

-- | /O(n)/ 'replicateChar' @n@ @c@ is a 'Text' of length @n@ with @c@ the
-- value of every element. Subject to fusion.
replicateChar :: Int -> Char -> Text
replicateChar n c = unstream (S.replicateCharI n (safe c))
{-# INLINE replicateChar #-}

-- | /O(n)/, where @n@ is the length of the result. The 'unfoldr'
-- function is analogous to the List 'L.unfoldr'. 'unfoldr' builds a
-- 'Text' from a seed value. The function takes the element and
-- returns 'Nothing' if it is done producing the 'Text', otherwise
-- 'Just' @(a,b)@.  In this case, @a@ is the next 'Char' in the
-- string, and @b@ is the seed value for further production. Subject
-- to fusion.  Performs replacement on invalid scalar values.
unfoldr     :: (a -> Maybe (Char,a)) -> a -> Text
unfoldr f s = unstream (S.unfoldr (firstf safe . f) s)
{-# INLINE unfoldr #-}

-- | /O(n)/ Like 'unfoldr', 'unfoldrN' builds a 'Text' from a seed
-- value. However, the length of the result should be limited by the
-- first argument to 'unfoldrN'. This function is more efficient than
-- 'unfoldr' when the maximum length of the result is known and
-- correct, otherwise its performance is similar to 'unfoldr'. Subject
-- to fusion.  Performs replacement on invalid scalar values.
unfoldrN     :: Int -> (a -> Maybe (Char,a)) -> a -> Text
unfoldrN n f s = unstream (S.unfoldrN n (firstf safe . f) s)
{-# INLINE unfoldrN #-}

-- -----------------------------------------------------------------------------
-- * Substrings

-- | /O(n)/ 'take' @n@, applied to a 'Text', returns the prefix of the
-- 'Text' of length @n@, or the 'Text' itself if @n@ is greater than
-- the length of the Text. Subject to fusion.

#ifndef VECFUNCTIONS

take :: Int -> Text -> Text
take n t@(Text arr off len)
    | n <= 0    = empty
    | n >= len  = t
    | otherwise = text arr off (iterN n t)
{-# INLINE [1] take #-}

{-# RULES
"TEXT take -> fused" [~1] forall n t.
    take n t = unstream (S.take n (stream t))
"TEXT take -> unfused" [1] forall n t.
    unstream (S.take n (stream t)) = take n t
  #-}

#else

take :: Int -> Text -> Text
take n t@(Text arr off0 _len0) = case nthCodepoint n t of
    -1 -> t
    x -> Text arr off0 x

#endif

iterN :: Int -> Text -> Int
iterN n t@(Text _arr _off len) = loop 0 0
  where loop !i !cnt
            | i >= len || cnt >= n = i
            | otherwise            = loop (i+d) (cnt+1)
          where d = iter_ t i


-- | /O(n)/ 'takeEnd' @n@ @t@ returns the suffix remaining after
-- taking @n@ characters from the end of @t@.
--
-- Examples:
--
-- >>> takeEnd 3 "foobar"
-- "bar"
--
-- @since 1.1.1.0
takeEnd :: Int -> Text -> Text
takeEnd n t@(Text arr off len)
    | n <= 0    = empty
    | n >= len  = t
    | otherwise = text arr (off+i) (len-i)
  where i = iterNEnd n t

iterNEnd :: Int -> Text -> Int
iterNEnd n t@(Text _arr _off len) = loop (len-1) n
  where loop i !m
          | m <= 0    = i+1
          | i <= 0    = 0
          | otherwise = loop (i+d) (m-1)
          where d = reverseIter_ t i

-- | /O(n)/ 'drop' @n@, applied to a 'Text', returns the suffix of the
-- 'Text' after the first @n@ characters, or the empty 'Text' if @n@
-- is greater than the length of the 'Text'. Subject to fusion.
#ifndef VECFUNCTIONS

drop :: Int -> Text -> Text
drop n t@(Text arr off len)
    | n <= 0    = t
    | n >= len  = empty
    | otherwise = text arr (off+i) (len-i)
  where i = iterN n t
{-# INLINE [1] drop #-}

{-# RULES
"TEXT drop -> fused" [~1] forall n t.
    drop n t = unstream (S.drop n (stream t))
"TEXT drop -> unfused" [1] forall n t.
    unstream (S.drop n (stream t)) = drop n t
  #-}

#else

drop :: Int -> Text -> Text
drop n t@(Text arr off0 len0) = case nthCodepoint n t of
    -1 -> empty
    x -> Text arr (off0+x) (len0-x)

#endif

-- | /O(n)/ 'dropEnd' @n@ @t@ returns the prefix remaining after
-- dropping @n@ characters from the end of @t@.
--
-- Examples:
--
-- >>> dropEnd 3 "foobar"
-- "foo"
--
-- @since 1.1.1.0
dropEnd :: Int -> Text -> Text
dropEnd n t@(Text arr off len)
    | n <= 0    = t
    | n >= len  = empty
    | otherwise = text arr off (iterNEnd n t)

-- | /O(n)/ 'takeWhile', applied to a predicate @p@ and a 'Text',
-- returns the longest prefix (possibly empty) of elements that
-- satisfy @p@.  Subject to fusion.
takeWhile :: (Char -> Bool) -> Text -> Text
takeWhile p t@(Text arr off len) = loop 0
  where loop !i | i >= len    = t
                | p c         = loop (i+d)
                | otherwise   = text arr off i
            where Iter c d    = iter t i
{-# INLINE [1] takeWhile #-}

{-# RULES
"TEXT takeWhile -> fused" [~1] forall p t.
    takeWhile p t = unstream (S.takeWhile p (stream t))
"TEXT takeWhile -> unfused" [1] forall p t.
    unstream (S.takeWhile p (stream t)) = takeWhile p t
  #-}

-- | /O(n)/ 'takeWhileEnd', applied to a predicate @p@ and a 'Text',
-- returns the longest suffix (possibly empty) of elements that
-- satisfy @p@.  Subject to fusion.
-- Examples:
--
-- >>> takeWhileEnd (=='o') "foo"
-- "oo"
--
-- @since 1.2.2.0
takeWhileEnd :: (Char -> Bool) -> Text -> Text
takeWhileEnd p t@(Text arr off len) = loop (len-1) len
  where loop !i !l | l <= 0    = t
                   | p c       = loop (i+d) (l+d)
                   | otherwise = text arr (off+l) (len-l)
            where (c,d)        = reverseIter t i
{-# INLINE [1] takeWhileEnd #-}

{-# RULES
"TEXT takeWhileEnd -> fused" [~1] forall p t.
    takeWhileEnd p t = S.reverse (S.takeWhile p (S.reverseStream t))
"TEXT takeWhileEnd -> unfused" [1] forall p t.
    S.reverse (S.takeWhile p (S.reverseStream t)) = takeWhileEnd p t
  #-}

-- | /O(n)/ 'dropWhile' @p@ @t@ returns the suffix remaining after
-- 'takeWhile' @p@ @t@. Subject to fusion.
dropWhile :: (Char -> Bool) -> Text -> Text
dropWhile p t@(Text arr off len) = loop 0 0
  where loop !i !l | l >= len  = empty
                   | p c       = loop (i+d) (l+d)
                   | otherwise = Text arr (off+i) (len-l)
            where Iter c d     = iter t i
{-# INLINE [1] dropWhile #-}

{-# RULES
"TEXT dropWhile -> fused" [~1] forall p t.
    dropWhile p t = unstream (S.dropWhile p (stream t))
"TEXT dropWhile -> unfused" [1] forall p t.
    unstream (S.dropWhile p (stream t)) = dropWhile p t
  #-}

-- | /O(n)/ 'dropWhileEnd' @p@ @t@ returns the prefix remaining after
-- dropping characters that satisfy the predicate @p@ from the end of
-- @t@.  Subject to fusion.
--
-- Examples:
--
-- >>> dropWhileEnd (=='.') "foo..."
-- "foo"
dropWhileEnd :: (Char -> Bool) -> Text -> Text
dropWhileEnd p t@(Text arr off len) = loop (len-1) len
  where loop !i !l | l <= 0    = empty
                   | p c       = loop (i+d) (l+d)
                   | otherwise = Text arr off l
            where (c,d)        = reverseIter t i
{-# INLINE [1] dropWhileEnd #-}

{-# RULES
"TEXT dropWhileEnd -> fused" [~1] forall p t.
    dropWhileEnd p t = S.reverse (S.dropWhile p (S.reverseStream t))
"TEXT dropWhileEnd -> unfused" [1] forall p t.
    S.reverse (S.dropWhile p (S.reverseStream t)) = dropWhileEnd p t
  #-}

-- | /O(n)/ 'dropAround' @p@ @t@ returns the substring remaining after
-- dropping characters that satisfy the predicate @p@ from both the
-- beginning and end of @t@.  Subject to fusion.
dropAround :: (Char -> Bool) -> Text -> Text
dropAround p = dropWhile p . dropWhileEnd p
{-# INLINE [1] dropAround #-}

-- | /O(n)/ Remove leading white space from a string.  Equivalent to:
--
-- > dropWhile isSpace
stripStart :: Text -> Text
stripStart = dropWhile isSpace
{-# INLINE [1] stripStart #-}

-- | /O(n)/ Remove trailing white space from a string.  Equivalent to:
--
-- > dropWhileEnd isSpace
stripEnd :: Text -> Text
stripEnd = dropWhileEnd isSpace
{-# INLINE [1] stripEnd #-}

-- | /O(n)/ Remove leading and trailing white space from a string.
-- Equivalent to:
--
-- > dropAround isSpace
strip :: Text -> Text
strip = dropAround isSpace
{-# INLINE [1] strip #-}

-- | /O(n)/ 'splitAt' @n t@ returns a pair whose first element is a
-- prefix of @t@ of length @n@, and whose second is the remainder of
-- the string. It is equivalent to @('take' n t, 'drop' n t)@.
#ifndef VECFUNCTIONS

splitAt :: Int -> Text -> (Text, Text)
splitAt n t@(Text arr off len)
    | n <= 0    = (empty, t)
    | n >= len  = (t, empty)
    | otherwise = let k = iterN n t
                  in (text arr off k, text arr (off+k) (len-k))
#else


splitAt :: Int -> Text -> (Text, Text)
splitAt n t@(Text arr off0 len0) = case nthCodepoint n t of
    -1 -> (t,empty)
    x -> (Text arr off0 x, Text arr (off0+x) (len0-x))


#endif


-- | /O(n)/ 'span', applied to a predicate @p@ and text @t@, returns
-- a pair whose first element is the longest prefix (possibly empty)
-- of @t@ of elements that satisfy @p@, and whose second is the
-- remainder of the list.
span :: (Char -> Bool) -> Text -> (Text, Text)
span p t = case span_ p t of
             (# hd,tl #) -> (hd,tl)
{-# INLINE span #-}

-- | /O(n)/ 'break' is like 'span', but the prefix returned is
-- over elements that fail the predicate @p@.
break :: (Char -> Bool) -> Text -> (Text, Text)
break p = span (not . p)
{-# INLINE break #-}

-- | /O(n)/ Group characters in a string according to a predicate.
groupBy :: (Char -> Char -> Bool) -> Text -> [Text]
groupBy p = loop
  where
    loop t@(Text arr off len)
        | null t    = []
        | otherwise = text arr off n : loop (text arr (off+n) (len-n))
        where Iter c d = iter t 0
              n     = d + findAIndexOrEnd (not . p c) (Text arr (off+d) (len-d))

-- | Returns the /array/ index (in units of 'Word16') at which a
-- character may be found.  This is /not/ the same as the logical
-- index returned by e.g. 'findIndex'.
findAIndexOrEnd :: (Char -> Bool) -> Text -> Int
findAIndexOrEnd q t@(Text _arr _off len) = go 0
    where go !i | i >= len || q c       = i
                | otherwise             = go (i+d)
                where Iter c d          = iter t i

-- | /O(n)/ Group characters in a string by equality.
group :: Text -> [Text]
group = groupBy (==)

-- | /O(n)/ Return all initial segments of the given 'Text', shortest
-- first.
inits :: Text -> [Text]
inits t@(Text arr off len) = loop 0
    where loop i | i >= len = [t]
                 | otherwise = Text arr off i : loop (i + iter_ t i)

-- | /O(n)/ Return all final segments of the given 'Text', longest
-- first.
tails :: Text -> [Text]
tails t | null t    = [empty]
        | otherwise = t : tails (unsafeTail t)

-- $split
--
-- Splitting functions in this library do not perform character-wise
-- copies to create substrings; they just construct new 'Text's that
-- are slices of the original.

-- | /O(m+n)/ Break a 'Text' into pieces separated by the first 'Text'
-- argument (which cannot be empty), consuming the delimiter. An empty
-- delimiter is invalid, and will cause an error to be raised.
--
-- Examples:
--
-- >>> splitOn "\r\n" "a\r\nb\r\nd\r\ne"
-- ["a","b","d","e"]
--
-- >>> splitOn "aaa"  "aaaXaaaXaaaXaaa"
-- ["","X","X","X",""]
--
-- >>> splitOn "x"    "x"
-- ["",""]
--
-- and
--
-- > intercalate s . splitOn s         == id
-- > splitOn (singleton c)             == split (==c)
--
-- (Note: the string @s@ to split on above cannot be empty.)
--
-- In (unlikely) bad cases, this function's time complexity degrades
-- towards /O(n*m)/.
splitOn :: Text
        -- ^ String to split on. If this string is empty, an error
        -- will occur.
        -> Text
        -- ^ Input text.
        -> [Text]
splitOn pat@(Text _ _ l) src@(Text arr off len)
    | l <= 0          = emptyError "splitOn"
    | isSingleton pat = split (== unsafeHead pat) src
    | otherwise       = go 0 (indices pat src)
  where
    go !s (x:xs) =  text arr (s+off) (x-s) : go (x+l) xs
    go  s _      = [text arr (s+off) (len-s)]
{-# INLINE [1] splitOn #-}

{-# RULES
"TEXT splitOn/singleton -> split/==" [~1] forall c t.
    splitOn (singleton c) t = split (==c) t
  #-}

-- | /O(n)/ Splits a 'Text' into components delimited by separators,
-- where the predicate returns True for a separator element.  The
-- resulting components do not contain the separators.  Two adjacent
-- separators result in an empty component in the output.  eg.
--
-- >>> split (=='a') "aabbaca"
-- ["","","bb","c",""]
--
-- >>> split (=='a') ""
-- [""]
split :: (Char -> Bool) -> Text -> [Text]
split _ t@(Text _off _arr 0) = [t]
split p t = loop t
    where loop s | null s'   = [l]
                 | otherwise = l : loop (unsafeTail s')
              where (# l, s' #) = span_ (not . p) s
{-# INLINE split #-}

-- | /O(n)/ Splits a 'Text' into components of length @k@.  The last
-- element may be shorter than the other chunks, depending on the
-- length of the input. Examples:
--
-- >>> chunksOf 3 "foobarbaz"
-- ["foo","bar","baz"]
--
-- >>> chunksOf 4 "haskell.org"
-- ["hask","ell.","org"]
chunksOf :: Int -> Text -> [Text]
chunksOf k = go
  where
    go t = case splitAt k t of
             (a,b) | null a    -> []
                   | otherwise -> a : go b
{-# INLINE chunksOf #-}

-- ----------------------------------------------------------------------------
-- * Searching

-------------------------------------------------------------------------------
-- ** Searching with a predicate

-- | /O(n)/ The 'find' function takes a predicate and a 'Text', and
-- returns the first element matching the predicate, or 'Nothing' if
-- there is no such element.
find :: (Char -> Bool) -> Text -> Maybe Char
find p t = S.findBy p (stream t)
{-# INLINE find #-}

-- | /O(n)/ The 'partition' function takes a predicate and a 'Text',
-- and returns the pair of 'Text's with elements which do and do not
-- satisfy the predicate, respectively; i.e.
--
-- > partition p t == (filter p t, filter (not . p) t)
partition :: (Char -> Bool) -> Text -> (Text, Text)
partition p t = (filter p t, filter (not . p) t)
{-# INLINE partition #-}

-- | /O(n)/ 'filter', applied to a predicate and a 'Text',
-- returns a 'Text' containing those characters that satisfy the
-- predicate.
filter :: (Char -> Bool) -> Text -> Text
filter p t = unstream (S.filter p (stream t))
{-# INLINE filter #-}

-- | /O(n+m)/ Find the first instance of @needle@ (which must be
-- non-'null') in @haystack@.  The first element of the returned tuple
-- is the prefix of @haystack@ before @needle@ is matched.  The second
-- is the remainder of @haystack@, starting with the match.
--
-- Examples:
--
-- >>> breakOn "::" "a::b::c"
-- ("a","::b::c")
--
-- >>> breakOn "/" "foobar"
-- ("foobar","")
--
-- Laws:
--
-- > append prefix match == haystack
-- >   where (prefix, match) = breakOn needle haystack
--
-- If you need to break a string by a substring repeatedly (e.g. you
-- want to break on every instance of a substring), use 'breakOnAll'
-- instead, as it has lower startup overhead.
--
-- In (unlikely) bad cases, this function's time complexity degrades
-- towards /O(n*m)/.
breakOn :: Text -> Text -> (Text, Text)
breakOn pat src@(Text arr off len)
    | null pat  = emptyError "breakOn"
    | otherwise = case indices pat src of
                    []    -> (src, empty)
                    (x:_) -> (text arr off x, text arr (off+x) (len-x))
{-# INLINE breakOn #-}

-- | /O(n+m)/ Similar to 'breakOn', but searches from the end of the
-- string.
--
-- The first element of the returned tuple is the prefix of @haystack@
-- up to and including the last match of @needle@.  The second is the
-- remainder of @haystack@, following the match.
--
-- >>> breakOnEnd "::" "a::b::c"
-- ("a::b::","c")
breakOnEnd :: Text -> Text -> (Text, Text)
breakOnEnd pat src = (reverse b, reverse a)
    where (a,b) = breakOn (reverse pat) (reverse src)
{-# INLINE breakOnEnd #-}

-- | /O(n+m)/ Find all non-overlapping instances of @needle@ in
-- @haystack@.  Each element of the returned list consists of a pair:
--
-- * The entire string prior to the /k/th match (i.e. the prefix)
--
-- * The /k/th match, followed by the remainder of the string
--
-- Examples:
--
-- >>> breakOnAll "::" ""
-- []
--
-- >>> breakOnAll "/" "a/b/c/"
-- [("a","/b/c/"),("a/b","/c/"),("a/b/c","/")]
--
-- In (unlikely) bad cases, this function's time complexity degrades
-- towards /O(n*m)/.
--
-- The @needle@ parameter may not be empty.
breakOnAll :: Text              -- ^ @needle@ to search for
           -> Text              -- ^ @haystack@ in which to search
           -> [(Text, Text)]
breakOnAll pat src@(Text arr off slen)
    | null pat  = emptyError "breakOnAll"
    | otherwise = L.map step (indices pat src)
  where
    step       x = (chunk 0 x, chunk x (slen-x))
    chunk !n !l  = text arr (n+off) l
{-# INLINE breakOnAll #-}

-------------------------------------------------------------------------------
-- ** Indexing 'Text's

-- $index
--
-- If you think of a 'Text' value as an array of 'Char' values (which
-- it is not), you run the risk of writing inefficient code.
--
-- An idiom that is common in some languages is to find the numeric
-- offset of a character or substring, then use that number to split
-- or trim the searched string.  With a 'Text' value, this approach
-- would require two /O(n)/ operations: one to perform the search, and
-- one to operate from wherever the search ended.
--
-- For example, suppose you have a string that you want to split on
-- the substring @\"::\"@, such as @\"foo::bar::quux\"@. Instead of
-- searching for the index of @\"::\"@ and taking the substrings
-- before and after that index, you would instead use @breakOnAll \"::\"@.

-- | /O(n)/ 'Text' index (subscript) operator, starting from 0.
index :: Text -> Int -> Char
index t n = S.index (stream t) n
{-# INLINE index #-}

-- | /O(n)/ The 'findIndex' function takes a predicate and a 'Text'
-- and returns the index of the first element in the 'Text' satisfying
-- the predicate. Subject to fusion.
findIndex :: (Char -> Bool) -> Text -> Maybe Int
findIndex p t = S.findIndex p (stream t)
{-# INLINE findIndex #-}

-- | /O(n+m)/ The 'count' function returns the number of times the
-- query string appears in the given 'Text'. An empty query string is
-- invalid, and will cause an error to be raised.
--
-- In (unlikely) bad cases, this function's time complexity degrades
-- towards /O(n*m)/.
count :: Text -> Text -> Int
count pat src
    | null pat        = emptyError "count"
    | isSingleton pat = countChar (unsafeHead pat) src
    | otherwise       = L.length (indices pat src)
{-# INLINE [1] count #-}

{-# RULES
"TEXT count/singleton -> countChar" [~1] forall c t.
    count (singleton c) t = countChar c t
  #-}

-- | /O(n)/ The 'countChar' function returns the number of times the
-- query element appears in the given 'Text'. Subject to fusion.
countChar :: Char -> Text -> Int
countChar c t = S.countChar c (stream t)
{-# INLINE countChar #-}

-------------------------------------------------------------------------------
-- * Zipping

-- | /O(n)/ 'zip' takes two 'Text's and returns a list of
-- corresponding pairs of bytes. If one input 'Text' is short,
-- excess elements of the longer 'Text' are discarded. This is
-- equivalent to a pair of 'unpack' operations.
zip :: Text -> Text -> [(Char,Char)]
zip a b = S.unstreamList $ S.zipWith (,) (stream a) (stream b)
{-# INLINE zip #-}

-- | /O(n)/ 'zipWith' generalises 'zip' by zipping with the function
-- given as the first argument, instead of a tupling function.
-- Performs replacement on invalid scalar values.
zipWith :: (Char -> Char -> Char) -> Text -> Text -> Text
zipWith f t1 t2 = unstream (S.zipWith g (stream t1) (stream t2))
    where g a b = safe (f a b)
{-# INLINE zipWith #-}

-- | /O(n)/ Breaks a 'Text' up into a list of words, delimited by 'Char's
-- representing white space.
words :: Text -> [Text]
words t@(Text arr off len) = loop 0 0
  where
    loop !start !n
        | n >= len = if start == n
                     then []
                     else [Text arr (start+off) (n-start)]
        | isSpace c =
            if start == n
            then loop (start+d) (start+d)
            else Text arr (start+off) (n-start) : loop (n+d) (n+d)
        | otherwise = loop start (n+d)
        where Iter c d = iter t n
{-# INLINE words #-}

-- | /O(n)/ Breaks a 'Text' up into a list of 'Text's at
-- newline 'Char's. The resulting strings do not contain newlines.
lines :: Text -> [Text]
lines ps | null ps   = []
         | otherwise = h : if null t
                           then []
                           else lines (unsafeTail t)
    where (# h,t #) = span_ (/= '\n') ps
{-# INLINE lines #-}

{-
-- | /O(n)/ Portably breaks a 'Text' up into a list of 'Text's at line
-- boundaries.
--
-- A line boundary is considered to be either a line feed, a carriage
-- return immediately followed by a line feed, or a carriage return.
-- This accounts for both Unix and Windows line ending conventions,
-- and for the old convention used on Mac OS 9 and earlier.
lines' :: Text -> [Text]
lines' ps | null ps   = []
          | otherwise = h : case uncons t of
                              Nothing -> []
                              Just (c,t')
                                  | c == '\n' -> lines t'
                                  | c == '\r' -> case uncons t' of
                                                   Just ('\n',t'') -> lines t''
                                                   _               -> lines t'
    where (h,t)    = span notEOL ps
          notEOL c = c /= '\n' && c /= '\r'
{-# INLINE lines' #-}
-}

-- | /O(n)/ Joins lines, after appending a terminating newline to
-- each.
unlines :: [Text] -> Text
unlines = concat . L.map (`snoc` '\n')
{-# INLINE unlines #-}

-- | /O(n)/ Joins words using single space characters.
unwords :: [Text] -> Text
unwords = intercalate (singleton ' ')
{-# INLINE unwords #-}

-- | /O(n)/ The 'isPrefixOf' function takes two 'Text's and returns
-- 'True' iff the first is a prefix of the second.  Subject to fusion.
isPrefixOf :: Text -> Text -> Bool
isPrefixOf a@(Text _ _ alen) b@(Text _ _ blen) =
    alen <= blen && S.isPrefixOf (stream a) (stream b)
{-# INLINE [1] isPrefixOf #-}

{-# RULES
"TEXT isPrefixOf -> fused" [~1] forall s t.
    isPrefixOf s t = S.isPrefixOf (stream s) (stream t)
  #-}

-- | /O(n)/ The 'isSuffixOf' function takes two 'Text's and returns
-- 'True' iff the first is a suffix of the second.
isSuffixOf :: Text -> Text -> Bool
isSuffixOf a@(Text _aarr _aoff alen) b@(Text barr boff blen) =
    d >= 0 && a == b'
  where d              = blen - alen
        b' | d == 0    = b
           | otherwise = Text barr (boff+d) alen
{-# INLINE isSuffixOf #-}

-- | /O(n+m)/ The 'isInfixOf' function takes two 'Text's and returns
-- 'True' iff the first is contained, wholly and intact, anywhere
-- within the second.
--
-- In (unlikely) bad cases, this function's time complexity degrades
-- towards /O(n*m)/.
isInfixOf :: Text -> Text -> Bool
isInfixOf needle haystack
    | null needle        = True
    | isSingleton needle = S.elem (unsafeHead needle) . S.stream $ haystack
    | otherwise          = not . L.null . indices needle $ haystack
{-# INLINE [1] isInfixOf #-}

{-# RULES
"TEXT isInfixOf/singleton -> S.elem/S.stream" [~1] forall n h.
    isInfixOf (singleton n) h = S.elem n (S.stream h)
  #-}

-------------------------------------------------------------------------------
-- * View patterns

-- | /O(n)/ Return the suffix of the second string if its prefix
-- matches the entire first string.
--
-- Examples:
--
-- >>> stripPrefix "foo" "foobar"
-- Just "bar"
--
-- >>> stripPrefix ""    "baz"
-- Just "baz"
--
-- >>> stripPrefix "foo" "quux"
-- Nothing
--
-- This is particularly useful with the @ViewPatterns@ extension to
-- GHC, as follows:
--
-- > {-# LANGUAGE ViewPatterns #-}
-- > import Data.Text as T
-- >
-- > fnordLength :: Text -> Int
-- > fnordLength (stripPrefix "fnord" -> Just suf) = T.length suf
-- > fnordLength _                                 = -1
stripPrefix :: Text -> Text -> Maybe Text
stripPrefix p@(Text _arr _off plen) t@(Text arr off len)
    | p `isPrefixOf` t = Just $! text arr (off+plen) (len-plen)
    | otherwise        = Nothing

-- | /O(n)/ Find the longest non-empty common prefix of two strings
-- and return it, along with the suffixes of each string at which they
-- no longer match.
--
-- If the strings do not have a common prefix or either one is empty,
-- this function returns 'Nothing'.
--
-- Examples:
--
-- >>> commonPrefixes "foobar" "fooquux"
-- Just ("foo","bar","quux")
--
-- >>> commonPrefixes "veeble" "fetzer"
-- Nothing
--
-- >>> commonPrefixes "" "baz"
-- Nothing
commonPrefixes :: Text -> Text -> Maybe (Text,Text,Text)
commonPrefixes t0@(Text arr0 off0 len0) t1@(Text arr1 off1 len1) = go 0 0
  where
    go !i !j | i < len0 && j < len1 && a == b = go (i+d0) (j+d1)
             | i > 0     = Just (Text arr0 off0 i,
                                 text arr0 (off0+i) (len0-i),
                                 text arr1 (off1+j) (len1-j))
             | otherwise = Nothing
      where Iter a d0 = iter t0 i
            Iter b d1 = iter t1 j

-- | /O(n)/ Return the prefix of the second string if its suffix
-- matches the entire first string.
--
-- Examples:
--
-- >>> stripSuffix "bar" "foobar"
-- Just "foo"
--
-- >>> stripSuffix ""    "baz"
-- Just "baz"
--
-- >>> stripSuffix "foo" "quux"
-- Nothing
--
-- This is particularly useful with the @ViewPatterns@ extension to
-- GHC, as follows:
--
-- > {-# LANGUAGE ViewPatterns #-}
-- > import Data.Text as T
-- >
-- > quuxLength :: Text -> Int
-- > quuxLength (stripSuffix "quux" -> Just pre) = T.length pre
-- > quuxLength _                                = -1
stripSuffix :: Text -> Text -> Maybe Text
stripSuffix p@(Text _arr _off plen) t@(Text arr off len)
    | p `isSuffixOf` t = Just $! text arr off (len-plen)
    | otherwise        = Nothing

-- | Add a list of non-negative numbers.  Errors out on overflow.
sumP :: String -> [Int] -> Int
sumP fun = go 0
  where go !a (x:xs)
            | ax >= 0   = go ax xs
            | otherwise = overflowError fun
          where ax = a + x
        go a  _         = a

emptyError :: String -> a
emptyError fun = P.error $ "Data.Text." ++ fun ++ ": empty input"

overflowError :: String -> a
overflowError fun = P.error $ "Data.Text." ++ fun ++ ": size overflow"

-- | /O(n)/ Make a distinct copy of the given string, sharing no
-- storage with the original string.
--
-- As an example, suppose you read a large string, of which you need
-- only a small portion.  If you do not use 'copy', the entire original
-- array will be kept alive in memory by the smaller string. Making a
-- copy \"breaks the link\" to the original array, allowing it to be
-- garbage collected if there are no other live references to it.
copy :: Text -> Text
copy (Text arr off len) = Text (A.run go) 0 len
  where
    go :: ST s (A.MArray s)
    go = do
      marr <- A.new len
      A.copyI marr 0 arr off len
      return marr


-------------------------------------------------
-- NOTE: the named chunk below used by doctest;
--       verify the doctests via `doctest -fobject-code Data/Text.hs`

-- $setup
-- >>> :set -XOverloadedStrings
-- >>> import qualified Data.Text as T
