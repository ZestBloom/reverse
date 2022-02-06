'reach 0.1';
'use strict'
// -----------------------------------------------
// Name: ALGO/ETH/CFX NFT Jam Reverse Auction
// Author: Nicholas Shellabarger
// Version: 0.1.0 - add cancel
// Requires Reach v0.1.7
// -----------------------------------------------
// FUNCS
import { max, min } from '@nash-protocol/starter-kit:util.rsh'
export const minBidFunc = (currentPrice, [bidIncrementAbs, bidIncrementRel]) =>
  max(currentPrice + bidIncrementAbs,
    currentPrice + (currentPrice / 100) * bidIncrementRel)
// INTERACTS
export const common = {
  ...hasConsoleLogger,
  close: Fun([], Null)
}
export const hasSignal = {
  signal: Fun([], Null)
}
export const relayInteract = {
  ...common
}
export const depositerInteract = ({
  ...common,
  ...hasSignal
})
// PARTICIPANTS
export const Participants = () => [
  Participant('Relay', relayInteract),
  Participant('Depositer', depositerInteract),
  Participant('Auctioneer', {
    ...common,
    ...hasSignal,
    getParams: Fun([], Object({
      token: Token, // NFT token
      creator: Address, // Creator
      startPrice: UInt, // 100
      floorPrice: UInt, // 1
    }))
  })
]
export const Views = () => [
  View('Auction', {
    token: Token,
    currentPrice: UInt,
    startPrice: UInt,
    floorPrice: UInt,
    closed: Bool
  })
]
export const Api = () => [
  API('Bid', {
    touch: Fun([], Null),
    acceptOffer: Fun([], Null),
    cancel: Fun([], Null),
  })
]
export const App = (map) => {
  const [
    { 
      addr, // discovery
      addr2  // platform
    },
    {
      tok 
    },
    [Relay, Depositer, Auctioneer],
    [Auction],
    [Bid]
  ] = map;
  // ---------------------------------------------
  // Auctioneer publishes prarams and deposits token
  // ---------------------------------------------
  Auctioneer.only(() => {
    const {
      token,
      creator, // TODO add royalties
      startPrice,
      floorPrice,
    } = declassify(interact.getParams());
    assume(floorPrice > 0)
    assume(floorPrice < startPrice)
    assume(tok !== token)
  })
  Auctioneer
    .publish(
      token,
      creator,
      startPrice,
      floorPrice
    )
    .pay(100000) // 0.1 ALGO from auctioneer
  require(floorPrice > 0)
  require(floorPrice < startPrice)
  require(tok != token)

  Auction.startPrice.set(startPrice)
  Auction.floorPrice.set(floorPrice)
  Auction.token.set(token)
  Auction.closed.set(false)

  Auctioneer.only(() => interact.signal());
  
  // Auctioneer done  

  transfer(100000).to(addr) // 0.1 ALGO to discovery

  Depositer.set(Auctioneer)

  commit()

  Depositer
    .pay([[1, token]]) // TODO allow token amt to be set in params
    .when(true)

  Depositer.only(() => interact.signal());
  each([Depositer], () => interact.log("Start Auction"));

  // Depositer done

  const referenceConcensusTime = lastConsensusTime()
  const [
    keepGoing,
    currentPrice
  ] =
    parallelReduce([
      true,
      startPrice
    ])
      .define(() => {
        Auction.currentPrice.set(currentPrice)
      })
      .invariant(balance() >= 0)
      .while(keepGoing)
      .api(Bid.touch,
        (() => assume(currentPrice >= floorPrice)),
        (() => 0),
        ((k) => {
          require(currentPrice >= floorPrice)
          k(null)
          return [
            true,
            max(
              floorPrice,
              (diff =>
                startPrice <= diff
                  ? floorPrice
                  : startPrice - diff)
                (min(
                  ((lastConsensusTime() - referenceConcensusTime) / 15) * 10 * 1000000,
                  startPrice - floorPrice)))
          ]
        })
      )
      .api(Bid.acceptOffer,
        (() => assume(true)),
        (() => currentPrice),
        ((k) => {
          require(true)
          k(null)
          const cent = balance() / 100
          const platformAmount = cent
          const recvAmount = balance() - platformAmount
          transfer(recvAmount).to(Auctioneer)
          transfer([[balance(token), token]]).to(this)
          return [
            false,
            currentPrice
          ]
        }))
      .api(Bid.cancel,
        (() => assume(this === Auctioneer)),
        (() => 0),
        ((k) => {
          require(this === Auctioneer)
          k(null)
          transfer([[balance(token), token]]).to(this)
          return [
            false,
            currentPrice
          ]
        }))
      .timeout(false)
  Auction.closed.set(true) // Set View Closed
  commit()
  Relay.publish()
  transfer(balance()).to(addr2)
  transfer([[balance(token), token]]).to(addr2)
  transfer([[balance(tok), tok]]).to(addr2)
  commit();
  exit();

}
// -----------------------------------------------