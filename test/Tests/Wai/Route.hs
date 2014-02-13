{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators     #-}

module Tests.Wai.Route (tests) where

import Data.ByteString (ByteString)
import Data.String
import Network.HTTP.Types
import Network.Wai
import Network.Wai.Routing hiding (Request)
import Test.HUnit hiding (Test)
import Test.Tasty
import Test.Tasty.HUnit
import Tests.Wai.Util

import qualified Data.ByteString.Lazy  as Lazy
import qualified Network.Wai.Routing   as R

tests :: TestTree
tests = testGroup "Network.Wai.Routing"
    [ testCase "Sitemap" testSitemap
    , testCase "Media Selection" testMedia
    ]

testSitemap :: IO ()
testSitemap = do
    let routes  = expand sitemap
    assertEqual "Endpoints"
        ["/a", "/b", "/c", "/d", "/e", "/f", "/g"]
        (map fst routes)

    let handler = route sitemap
    testEndpointA handler
    testEndpointB handler
    testEndpointC handler
    testEndpointD handler
    testEndpointE handler
    testEndpointF handler

sitemap :: Routes IO ()
sitemap = do
    get "/a" handlerA $
        Accept :&: (Query "name" :|: Query "nick") :&: Query "foo"

    get "/b" handlerB $
        Query "baz"

    get "/c" handlerC $
        Opt (Query "foo")

    get "/d" handlerD $
        Def 0 (Query "foo")

    get "/e" handlerE $
        Def 0 (Hdr "foo")

    get "/f" handlerF $
        Query "foo"

    get "/g" handlerG true

handlerA :: Media "application" "json" ::: Int ::: ByteString -> IO Response
handlerA (_ ::: i ::: _) = writeText (fromString . show $ i)

handlerB :: Int -> IO Response
handlerB baz = writeText (fromString . show $ baz)

handlerC :: Maybe Int -> IO Response
handlerC foo = writeText (fromString . show $ foo)

handlerD :: Int -> IO Response
handlerD foo = writeText (fromString . show $ foo)

handlerE :: Int -> IO Response
handlerE foo = writeText (fromString . show $ foo)

handlerF :: [Int] -> IO Response
handlerF foo = writeText (fromString . show . sum $ foo)

handlerG :: () -> IO Response
handlerG = const $ writeText "all good"

testEndpointA :: Application -> Assertion
testEndpointA f = do
    let rq = defaultRequest { rawPathInfo = "/a" }

    rs0 <- f $ withHeader "Accept" "foo/bar" rq
    status406 @=? responseStatus rs0

    rs1 <- f $ json rq
    status400 @=? responseStatus rs1

    rs2 <- f . json . withQuery "name" "x" $ rq
    status400 @=? responseStatus rs2

    rs3 <- f . json . withQuery "name" "123" . withQuery "foo" "\"z\"" $ rq
    status200 @=? responseStatus rs3


testEndpointB :: Application -> Assertion
testEndpointB f = do
    let rq = defaultRequest { rawPathInfo = "/b" }

    rs0 <- f rq
    status400 @=? responseStatus rs0
    "Missing query 'baz'." @=? responseBody rs0

    rs1 <- f . withQuery "baz" "abc" $ rq
    status400 @=? responseStatus rs1
    "Failed reading: Invalid Int" @=? responseBody rs1

    rs2 <- f . withQuery "baz" "abc" . withQuery "baz" "123" $ rq
    status200 @=? responseStatus rs2
    "123" @=? responseBody rs2


testEndpointC :: Application -> Assertion
testEndpointC f = do
    let rq = defaultRequest { rawPathInfo = "/c" }

    rs0 <- f rq
    status200 @=? responseStatus rs0
    "Nothing" @=? responseBody rs0

    rs1 <- f . withQuery "foo" "abc" . withQuery "foo" "123" $ rq
    status200  @=? responseStatus rs1
    "Just 123" @=? responseBody rs1

    rs2 <- f . withQuery "foo" "abc" $ rq
    status200 @=? responseStatus rs2


testEndpointD :: Application -> Assertion
testEndpointD f = do
    let rq = defaultRequest { rawPathInfo = "/d" }

    rs0 <- f rq
    status200 @=? responseStatus rs0
    "0"       @=? responseBody rs0

    rs1 <- f . withQuery "foo" "xxx" . withQuery "foo" "42" $ rq
    status200 @=? responseStatus rs1
    "42"      @=? responseBody rs1

    rs2 <- f . withQuery "foo" "yyy" $ rq
    status200 @=? responseStatus rs2
    "0"       @=? responseBody rs2


testEndpointE :: Application -> Assertion
testEndpointE f = do
    let rq = defaultRequest { rawPathInfo = "/e" }

    rs0 <- f rq
    status200 @=? responseStatus rs0
    "0"       @=? responseBody rs0

    rs1 <- f $ withHeader "foo" "42" rq
    status200 @=? responseStatus rs1
    "42"      @=? responseBody rs1

    rs2 <- f $ withHeader "foo" "abc" rq
    status200 @=? responseStatus rs2
    "0"       @=? responseBody rs2


testEndpointF :: Application -> Assertion
testEndpointF f = do
    let rq = defaultRequest { rawPathInfo = "/f" }

    rs0 <- f . withQuery "foo" "1,2,3,4" $ rq
    status200 @=? responseStatus rs0
    "10"      @=? responseBody rs0


-----------------------------------------------------------------------------
-- Media Selection Tests

testMedia :: IO ()
testMedia = do
    let [(_, h)] = expand sitemapMedia
    expectMedia "application/json;q=0.3, application/x-thrift;q=0.7" "application/x-thrift" h
    expectMedia "application/json;q=0.7, application/x-thrift;q=0.3" "application/json" h

sitemapMedia :: Routes IO ()
sitemapMedia = do
    get "/media" handlerJson   Accept
    get "/media" handlerThrift Accept

handlerJson :: Media "application" "json" -> IO Response
handlerJson _ = writeText "application/json"

handlerThrift :: Media "application" "x-thrift" -> IO Response
handlerThrift _ = writeText "application/x-thrift"

expectMedia :: ByteString -> ByteString -> (R.Request -> IO Response) -> Assertion
expectMedia h res m = do
    let rq = defaultRequest { rawPathInfo = "/media" }
    rs <- m . fromWaiRequest [] . withHeader "Accept" h $ rq
    Lazy.fromStrict res @=? responseBody rs
