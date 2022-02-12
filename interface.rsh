"reach 0.1";
"use strict";
// -----------------------------------------------
// Name: ALGO/ETH/CFX NFT Jam Reverse Auction
// Author: Nicholas Shellabarger
// Version: 0.2.2 - use fixed point artithmetic
//                  in price func
// Requires Reach v0.1.7
// -----------------------------------------------
// FUNCS
import { max, min } from "@nash-protocol/starter-kit:util.rsh";
/*
 * precision used in fixed point arithmetic
 */
const precision = 1000000;
/*
 * calculate price based on seconds elapsed since reference secs
 */
const priceFunc = (startPrice, floorPrice, referenceConcensusSecs, dk) =>
  max(
    floorPrice,
    ((diff) => (startPrice <= diff ? floorPrice : startPrice - diff))(
      min(
        ((lastConsensusSecs() - referenceConcensusSecs) * dk) / pre,
        startPrice - floorPrice
      )
    )
  );
// INTERACTS
const common = {
  ...hasConsoleLogger,
  close: Fun([], Null),
};
const hasSignal = {
  signal: Fun([], Null),
};
const relayInteract = {
  ...common,
};
const depositerInteract = {
  ...common,
  ...hasSignal,
};
const auctioneerInteract = {
  ...common,
  ...hasSignal,
  getParams: Fun(
    [],
    Object({
      token: Token, // NFT token
      creator: Address, // Creator
      startPrice: UInt, // 100
      floorPrice: UInt, // 1
      endSecs: UInt, // 1
    })
  ),
};
// PARTICIPANTS
export const Participants = () => [
  Participant("Relay", relayInteract),
  Participant("Depositer", depositerInteract),
  Participant("Auctioneer", auctioneerInteract),
];
export const Views = () => [
  View("Auction", {
    token: Token,
    currentPrice: UInt,
    startPrice: UInt,
    floorPrice: UInt,
    closed: Bool,
    endSecs: UInt,
    priceChangePerSec: UInt,
  }),
];
export const Api = () => [
  API("Bid", {
    touch: Fun([], Null),
    acceptOffer: Fun([], Null),
    cancel: Fun([], Null),
  }),
];
export const App = (map) => {
  const [
    {
      addr, // discovery
      addr2, // platform
      // TODO add royalties
      //addr3, // creator
    },
    { tok },
    [Relay, Depositer, Auctioneer],
    [Auction],
    [Bid],
  ] = map;
  // ---------------------------------------------
  // Auctioneer publishes prarams and deposits token
  // ---------------------------------------------
  Auctioneer.only(() => {
    const { token, startPrice, floorPrice, endSecs } = declassify(
      interact.getParams()
    );
    assume(floorPrice > 0);
    assume(floorPrice < startPrice);
    assume(tok !== token);
    assume(endSecs > 0);
  });
  Auctioneer.publish(token, startPrice, floorPrice, endSecs).pay(100000); // 0.1 ALGO from auctioneer
  require(floorPrice > 0);
  require(floorPrice < startPrice);
  require(tok != token);
  require(endSecs > 0);

  Auction.startPrice.set(startPrice);
  Auction.floorPrice.set(floorPrice);
  Auction.endSecs.set(endSecs);
  Auction.token.set(token);
  Auction.closed.set(false);

  Auctioneer.only(() => interact.signal());

  // Auctioneer done

  transfer(100000).to(addr); // 0.1 ALGO to discovery

  Depositer.set(Auctioneer);

  commit();

  Depositer.pay([[1, token]]) // TODO allow token amt to be set in params
    .when(true);

  Depositer.only(() => interact.signal());
  each([Depositer], () => interact.log("Start Auction"));

  // Depositer done

  const referenceConcensusSecs = lastConsensusSecs();
  // calculate slope
  const calc = (d, d2, p) => {
    const fD = fx(6)(Pos, d);
    const fD2 = fx(6)(Pos, d2);
    return fxdiv(fD, fD2, p);
  };
  const dk = calc(
    startPrice - floorPrice,
    endSecs - referenceConcensusSecs,
    precision
  ).i.i;
  Auction.priceChangePerSec.set(dk / precision);
  const [keepGoing, currentPrice] = parallelReduce([true, startPrice])
    .define(() => {
      Auction.currentPrice.set(currentPrice);
    })
    .invariant(balance() >= 0)
    .while(keepGoing)
    .api(
      Bid.touch,
      () => assume(currentPrice >= floorPrice),
      () => 0,
      (k) => {
        require(currentPrice >= floorPrice);
        k(null);
        return [
          true,
          priceFunc(startPrice, floorPrice, referenceConcensusSecs, dk),
        ];
      }
    )
    .api(
      Bid.acceptOffer,
      () => assume(true),
      () => currentPrice,
      (k) => {
        require(true);
        k(null);
        const cent = balance() / 100;
        const platformAmount = cent;
        const recvAmount = balance() - platformAmount;
        transfer(recvAmount).to(Auctioneer);
        transfer([[balance(token), token]]).to(this);
        return [false, currentPrice];
      }
    )
    .api(
      Bid.cancel,
      () => assume(this === Auctioneer),
      () => 0,
      (k) => {
        require(this === Auctioneer);
        k(null);
        transfer([[balance(token), token]]).to(this);
        return [false, currentPrice];
      }
    )
    .timeout(false);
  Auction.closed.set(true); // Set View Closed
  commit();
  Relay.publish();
  transfer(balance()).to(addr2);
  transfer([[balance(token), token]]).to(addr2);
  transfer([[balance(tok), tok]]).to(addr2);
  commit();
  exit();
};
// -----------------------------------------------
